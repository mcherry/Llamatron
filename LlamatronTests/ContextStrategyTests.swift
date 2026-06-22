import XCTest
@testable import Llamatron

final class ContextStrategyTests: XCTestCase {

    // MARK: - TokenEstimator

    func testTokenEstimateRoundsUp() {
        XCTAssertEqual(TokenEstimator.estimate(""), 0)
        XCTAssertEqual(TokenEstimator.estimate("abcd"), 1)       // 4 chars
        XCTAssertEqual(TokenEstimator.estimate("abcde"), 2)      // 5 chars -> ceil(1.25)
        XCTAssertEqual(TokenEstimator.estimate(["abcd", "abcd"]), 2)
    }

    // MARK: - ContextBudget

    func testBudgetReservesForResponseAndInputs() {
        let budget = ContextBudget(contextSize: 8192, systemTokens: 100, historyTokens: 200, userTokens: 50)
        // reserve = clamp(8192/4=2048) = 2048; used = 100+200+50+2048 = 2398
        XCTAssertEqual(budget.responseReserve, 2048)
        XCTAssertEqual(budget.availableForContext, 8192 - 2398)
    }

    func testBudgetNeverNegative() {
        let budget = ContextBudget(contextSize: 1000, systemTokens: 5000, historyTokens: 0, userTokens: 0)
        XCTAssertEqual(budget.availableForContext, 0)
    }

    func testBudgetResponseReserveBounds() {
        XCTAssertEqual(ContextBudget(contextSize: 1000, systemTokens: 0, historyTokens: 0, userTokens: 0).responseReserve, 512)
        XCTAssertEqual(ContextBudget(contextSize: 100000, systemTokens: 0, historyTokens: 0, userTokens: 0).responseReserve, 2048)
    }

    // MARK: - ContextPlanner: auto mode

    func testPlanAutoInlineWhenItFits() {
        let plan = ContextPlanner.plan(contentTokens: 100, available: 1000, mode: .auto, wholeDocTask: false)
        XCTAssertEqual(plan, [.inline, .retrieval, .summarize, .truncate])
    }

    func testPlanAutoRetrievalWhenTooBigAndFocused() {
        let plan = ContextPlanner.plan(contentTokens: 5000, available: 1000, mode: .auto, wholeDocTask: false)
        XCTAssertEqual(plan, [.retrieval, .summarize, .truncate])
    }

    func testPlanAutoSummarizeWhenTooBigAndWholeDoc() {
        let plan = ContextPlanner.plan(contentTokens: 5000, available: 1000, mode: .auto, wholeDocTask: true)
        XCTAssertEqual(plan, [.summarize, .retrieval, .truncate])
    }

    // MARK: - ContextPlanner: forced modes still fall back

    func testPlanForcedRetrieval() {
        let plan = ContextPlanner.plan(contentTokens: 5000, available: 1000, mode: .retrieval, wholeDocTask: false)
        XCTAssertEqual(plan, [.retrieval, .summarize, .truncate])
    }

    func testPlanForcedSummarize() {
        let plan = ContextPlanner.plan(contentTokens: 5000, available: 1000, mode: .summarize, wholeDocTask: false)
        XCTAssertEqual(plan, [.summarize, .retrieval, .truncate])
    }

    func testPlanForcedInline() {
        let plan = ContextPlanner.plan(contentTokens: 5000, available: 1000, mode: .inline, wholeDocTask: false)
        XCTAssertEqual(plan, [.inline, .retrieval, .summarize, .truncate])
    }

    func testPlanAlwaysEndsWithTruncate() {
        for mode in ContextMode.allCases {
            let plan = ContextPlanner.plan(contentTokens: 9999, available: 100, mode: mode, wholeDocTask: false)
            XCTAssertEqual(plan.last, .truncate, "mode \(mode) should fall back to truncate")
        }
    }

    func testPlanEmptyWhenNoContentOrBudget() {
        XCTAssertTrue(ContextPlanner.plan(contentTokens: 0, available: 1000, mode: .auto, wholeDocTask: false).isEmpty)
        XCTAssertTrue(ContextPlanner.plan(contentTokens: 100, available: 0, mode: .auto, wholeDocTask: false).isEmpty)
    }

    func testPlanHasNoDuplicates() {
        let plan = ContextPlanner.plan(contentTokens: 5000, available: 100, mode: .retrieval, wholeDocTask: false)
        XCTAssertEqual(plan.count, Set(plan).count)
    }

    // MARK: - Whole-doc heuristic

    func testWholeDocHeuristic() {
        XCTAssertTrue(ContextPlanner.looksLikeWholeDocTask("Please summarize this file"))
        XCTAssertTrue(ContextPlanner.looksLikeWholeDocTask("Give me an OVERVIEW"))
        XCTAssertTrue(ContextPlanner.looksLikeWholeDocTask("tl;dr?"))
        XCTAssertFalse(ContextPlanner.looksLikeWholeDocTask("What port does the server use?"))
    }

    // MARK: - Vector cosine

    func testCosineIdenticalIsOne() {
        XCTAssertEqual(Vector.cosineSimilarity([1, 2, 3], [1, 2, 3]), 1, accuracy: 1e-6)
    }

    func testCosineOrthogonalIsZero() {
        XCTAssertEqual(Vector.cosineSimilarity([1, 0], [0, 1]), 0, accuracy: 1e-6)
    }

    func testCosineMismatchedOrEmptyIsZero() {
        XCTAssertEqual(Vector.cosineSimilarity([1, 2, 3], [1, 2]), 0)
        XCTAssertEqual(Vector.cosineSimilarity([], []), 0)
        XCTAssertEqual(Vector.cosineSimilarity([0, 0], [0, 0]), 0)
    }

    func testCosineOppositeIsNegativeOne() {
        XCTAssertEqual(Vector.cosineSimilarity([1, 1], [-1, -1]), -1, accuracy: 1e-6)
    }

    // MARK: - TextChunker

    func testChunkerEmpty() {
        XCTAssertTrue(TextChunker().chunk("   ").isEmpty)
    }

    func testChunkerSmallTextIsOneChunk() {
        let chunks = TextChunker(targetTokens: 100, overlapTokens: 0).chunk("Hello world")
        XCTAssertEqual(chunks, ["Hello world"])
    }

    func testChunkerSplitsByParagraphWithinBudget() {
        // targetTokens 10 -> ~40 chars per chunk.
        let para = String(repeating: "a", count: 30)
        let text = "\(para)\n\n\(para)\n\n\(para)"
        let chunks = TextChunker(targetTokens: 10, overlapTokens: 0).chunk(text)
        XCTAssertGreaterThan(chunks.count, 1)
        // Every chunk should contain the source content somewhere.
        XCTAssertTrue(chunks.allSatisfy { $0.contains("a") })
    }

    func testChunkerHardSplitsLongParagraph() {
        let huge = String(repeating: "x", count: 500)   // far over a 10-token (~40 char) budget
        let chunks = TextChunker(targetTokens: 10, overlapTokens: 0).chunk(huge)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.joined(), huge)
    }

    // MARK: - TextTruncator

    func testTruncatorShortTextUnchanged() {
        XCTAssertEqual(TextTruncator.truncate("short", toTokens: 100), "short")
    }

    func testTruncatorClipsAndKeepsHeadAndTail() {
        let text = String(repeating: "A", count: 200) + String(repeating: "Z", count: 200)
        let result = TextTruncator.truncate(text, toTokens: 20) // ~80 chars budget
        XCTAssertLessThan(result.count, text.count)
        XCTAssertTrue(result.hasPrefix("A"))
        XCTAssertTrue(result.hasSuffix("Z"))
        XCTAssertTrue(result.contains("trimmed"))
    }

    func testTruncatorZeroBudgetIsEmpty() {
        XCTAssertEqual(TextTruncator.truncate("anything", toTokens: 0), "")
    }

    // MARK: - DocumentChunk embedding round-trip

    func testEmbeddingEncodeDecodeRoundTrip() {
        let original: [Float] = [0.1, -0.5, 3.14159, 0, 42]
        let restored = DocumentChunk.decode(DocumentChunk.encode(original))
        XCTAssertEqual(restored.count, original.count)
        for (a, b) in zip(original, restored) {
            XCTAssertEqual(a, b, accuracy: 1e-6)
        }
    }

    // MARK: - Embedding model detection

    func testEmbeddingModelFlag() {
        XCTAssertTrue(OllamaModel(name: "nomic-embed-text", details: nil).isEmbeddingModel)
        XCTAssertFalse(OllamaModel(name: "qwen-14b", details: nil).isEmbeddingModel)
    }
}

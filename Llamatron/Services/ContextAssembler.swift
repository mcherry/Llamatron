import Foundation

/// A chunk handed to the assembler. A plain `Sendable` value (never a SwiftData
/// `@Model`), so it can cross actor boundaries safely. `id` lets the caller write a
/// freshly computed embedding back to the persistent chunk.
struct RetrievableChunk: Sendable {
    let id: UUID
    let sourceName: String
    /// Global order across all attachments, for readable assembly.
    let ordinal: Int
    let text: String
    var embedding: [Float]?
}

/// A retrieved chunk plus its relevance score, for the retrieval inspector. A plain
/// `Codable`/`Sendable` value persisted (encoded) on the assistant message.
struct RetrievedChunkInfo: Codable, Sendable, Identifiable {
    var id: UUID
    var sourceName: String
    var ordinal: Int
    var score: Float
    var text: String
}

/// The result of assembling context: the text block to inject, which strategy won,
/// the sources used, any newly computed embeddings to persist, and a short note for
/// the UI. All `Sendable`.
struct AssembledContext: Sendable {
    var contextText: String
    var strategyUsed: ContextStrategy
    var sourceLabels: [String]
    var newEmbeddings: [UUID: [Float]]
    var note: String?
    var attempted: [ContextStrategy]
    /// Per-chunk relevance scores when the retrieval strategy ran; empty otherwise.
    var retrieved: [RetrievedChunkInfo] = []
}

/// Runs the strategy ladder produced by `ContextPlanner`: it tries each strategy in
/// order and falls through to the next on failure (e.g. the embedding endpoint is
/// down → drop from retrieval to summarize to truncate), so it always yields
/// *something* usable. Operates purely on `Sendable` values and `OllamaClient`.
struct ContextAssembler: Sendable {
    var client: OllamaClient
    /// The session's chat model, reused for map-reduce summarization.
    var chatModel: String
    var embeddingModel: String

    func assemble(chunks: [RetrievableChunk],
                  query: String,
                  available: Int,
                  plan: [ContextStrategy]) async -> AssembledContext? {
        guard !chunks.isEmpty, !plan.isEmpty, available > 0 else { return nil }

        var attempted: [ContextStrategy] = []
        for strategy in plan {
            attempted.append(strategy)
            do {
                switch strategy {
                case .inline:
                    return inline(chunks, attempted: attempted)
                case .truncate:
                    return truncate(chunks, available: available, attempted: attempted)
                case .retrieval:
                    return try await retrieve(chunks, query: query, available: available, attempted: attempted)
                case .summarize:
                    return try await summarize(chunks, query: query, available: available, attempted: attempted)
                }
            } catch is CancellationError {
                return nil
            } catch {
                continue // graceful fallback to the next strategy
            }
        }
        return nil
    }

    // MARK: - Strategies

    private func inline(_ chunks: [RetrievableChunk], attempted: [ContextStrategy]) -> AssembledContext {
        let ordered = chunks.sorted { $0.ordinal < $1.ordinal }
        return AssembledContext(
            contextText: render(ordered),
            strategyUsed: .inline,
            sourceLabels: labels(for: ordered),
            newEmbeddings: [:],
            note: nil,
            attempted: attempted
        )
    }

    private func truncate(_ chunks: [RetrievableChunk], available: Int, attempted: [ContextStrategy]) -> AssembledContext {
        let ordered = chunks.sorted { $0.ordinal < $1.ordinal }
        let joined = ordered.map(\.text).joined(separator: "\n\n")
        let clipped = TextTruncator.truncate(joined, toTokens: available)
        return AssembledContext(
            contextText: clipped,
            strategyUsed: .truncate,
            sourceLabels: labels(for: ordered),
            newEmbeddings: [:],
            note: "Content was truncated to fit the context budget.",
            attempted: attempted
        )
    }

    private func retrieve(_ chunks: [RetrievableChunk],
                          query: String,
                          available: Int,
                          attempted: [ContextStrategy]) async throws -> AssembledContext {
        // Embed any chunks that don't have a cached vector yet (nomic wants the
        // `search_document:` task prefix).
        var working = chunks
        var newEmbeddings: [UUID: [Float]] = [:]
        let missing = working.enumerated().filter { $0.element.embedding == nil }
        if !missing.isEmpty {
            let vectors = try await client.embed(model: embeddingModel,
                                                 input: missing.map { "search_document: " + $0.element.text })
            for (vectorIndex, item) in missing.enumerated() {
                working[item.offset].embedding = vectors[vectorIndex]
                newEmbeddings[item.element.id] = vectors[vectorIndex]
            }
        }

        // Embed the query (`search_query:` prefix) and score every chunk.
        let queryVector = try await client.embed(model: embeddingModel,
                                                 input: ["search_query: " + query]).first ?? []
        guard !queryVector.isEmpty else { throw OllamaError.server("Empty query embedding.") }

        let scored = working.compactMap { chunk -> (chunk: RetrievableChunk, score: Float)? in
            guard let embedding = chunk.embedding else { return nil }
            return (chunk, Vector.cosineSimilarity(queryVector, embedding))
        }.sorted { $0.score > $1.score }

        // Greedily take the highest-scoring chunks that fit the budget.
        var selected: [RetrievableChunk] = []
        var used = 0
        for candidate in scored {
            let tokens = TokenEstimator.estimate(candidate.chunk.text)
            if !selected.isEmpty, used + tokens > available { break }
            selected.append(candidate.chunk)
            used += tokens
            if used >= available { break }
        }
        guard !selected.isEmpty else { throw OllamaError.server("No relevant content found.") }

        let selectedIDs = Set(selected.map(\.id))
        let retrieved = scored
            .filter { selectedIDs.contains($0.chunk.id) }
            .map { RetrievedChunkInfo(id: $0.chunk.id,
                                     sourceName: $0.chunk.sourceName,
                                     ordinal: $0.chunk.ordinal,
                                     score: $0.score,
                                     text: $0.chunk.text) }

        let ordered = selected.sorted { $0.ordinal < $1.ordinal }
        return AssembledContext(
            contextText: render(ordered),
            strategyUsed: .retrieval,
            sourceLabels: labels(for: ordered),
            newEmbeddings: newEmbeddings,
            note: "Using \(selected.count) of \(chunks.count) excerpts most relevant to your question.",
            attempted: attempted,
            retrieved: retrieved
        )
    }

    private func summarize(_ chunks: [RetrievableChunk],
                           query: String,
                           available: Int,
                           attempted: [ContextStrategy]) async throws -> AssembledContext {
        // Map: summarize each chunk with the task in view.
        var summaries: [String] = []
        for chunk in chunks.sorted(by: { $0.ordinal < $1.ordinal }) {
            summaries.append(try await summarizeOne(chunk.text, query: query))
        }

        // Reduce: collapse the summaries until they fit (bounded iterations).
        var combined = summaries.joined(separator: "\n\n")
        var iterations = 0
        while TokenEstimator.estimate(combined) > available, iterations < 3, summaries.count > 1 {
            combined = try await summarizeOne(combined, query: query)
            iterations += 1
        }
        if TokenEstimator.estimate(combined) > available {
            combined = TextTruncator.truncate(combined, toTokens: available)
        }

        return AssembledContext(
            contextText: combined,
            strategyUsed: .summarize,
            sourceLabels: labels(for: chunks),
            newEmbeddings: [:],
            note: "Summarized \(chunks.count) sections of the attached content.",
            attempted: attempted
        )
    }

    private func summarizeOne(_ text: String, query: String) async throws -> String {
        let system = "You compress documents so they can be used to answer a question later. Summarize the text, preserving facts, names, numbers, and anything relevant to the user's task. Be concise and output only the summary."
        let user = "User's task: \(query)\n\nText:\n\(text)\n\nSummary:"
        let request = ChatRequest(
            model: chatModel,
            messages: [
                ChatTurn(role: Role.system.rawValue, content: system),
                ChatTurn(role: Role.user.rawValue, content: user)
            ],
            contextSize: 8192,
            stream: false,
            numPredict: 512,
            think: false
        )
        var output = ""
        for try await chunk in client.chat(request) {
            output += chunk.contentDelta
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OllamaError.server("Empty summary.") }
        return trimmed
    }

    // MARK: - Rendering

    private func render(_ chunks: [RetrievableChunk]) -> String {
        chunks.map { "[\($0.sourceName)]\n\($0.text)" }.joined(separator: "\n\n")
    }

    private func labels(for chunks: [RetrievableChunk]) -> [String] {
        Array(Set(chunks.map(\.sourceName))).sorted()
    }
}

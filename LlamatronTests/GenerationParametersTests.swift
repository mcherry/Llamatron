import XCTest
@testable import Llamatron

final class GenerationParametersTests: XCTestCase {

    // MARK: - GenerationParameters

    func testIsEmptyWhenUnset() {
        XCTAssertTrue(GenerationParameters().isEmpty)
    }

    func testIsNotEmptyWithSeed() {
        XCTAssertFalse(GenerationParameters(seed: 42).isEmpty)
    }

    func testIsNotEmptyWithStop() {
        XCTAssertFalse(GenerationParameters(stop: ["END"]).isEmpty)
    }

    // MARK: - ChatSession.generationParameters

    func testSessionParametersReflectFields() {
        let session = ChatSession(modelName: "qwen")
        session.temperature = 0.7
        session.seed = 99
        session.stopSequences = ["STOP"]

        let p = session.generationParameters
        XCTAssertEqual(p.temperature, 0.7)
        XCTAssertEqual(p.seed, 99)
        XCTAssertEqual(p.stop, ["STOP"])
        XCTAssertNil(p.topP)
    }

    // MARK: - Wire encoding

    private func encodedOptions(_ request: ChatRequest) throws -> [String: Any] {
        let data = try OllamaClient.encodeChatBody(request)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(json["options"] as? [String: Any])
    }

    func testEncodesAllParametersWithSnakeCaseKeys() throws {
        let params = GenerationParameters(temperature: 0.7, topP: 0.9, topK: 40,
                                          repeatPenalty: 1.1, seed: 42, stop: ["END", "STOP"])
        let request = ChatRequest(model: "qwen",
                                  messages: [ChatTurn(role: "user", content: "hi")],
                                  contextSize: 4096,
                                  parameters: params)
        let options = try encodedOptions(request)

        XCTAssertEqual(options["temperature"] as? Double, 0.7)
        XCTAssertEqual(options["top_p"] as? Double, 0.9)
        XCTAssertEqual(options["top_k"] as? Int, 40)
        XCTAssertEqual(options["repeat_penalty"] as? Double, 1.1)
        XCTAssertEqual(options["seed"] as? Int, 42)
        XCTAssertEqual(options["num_ctx"] as? Int, 4096)
        XCTAssertEqual(options["stop"] as? [String], ["END", "STOP"])
    }

    func testOmitsUnsetParameters() throws {
        let request = ChatRequest(model: "qwen", messages: [], contextSize: 8192)
        let options = try encodedOptions(request)

        XCTAssertNil(options["temperature"])
        XCTAssertNil(options["top_p"])
        XCTAssertNil(options["top_k"])
        XCTAssertNil(options["repeat_penalty"])
        XCTAssertNil(options["seed"])
        XCTAssertNil(options["stop"])
        XCTAssertEqual(options["num_ctx"] as? Int, 8192)
    }

    func testSeedAloneIsEncoded() throws {
        let request = ChatRequest(model: "qwen", messages: [], contextSize: 4096,
                                  parameters: GenerationParameters(seed: 7))
        let options = try encodedOptions(request)
        XCTAssertEqual(options["seed"] as? Int, 7)
        XCTAssertNil(options["temperature"])
    }

    func testThinkOmittedWhenNil() throws {
        let request = ChatRequest(model: "qwen", messages: [], contextSize: 4096)
        let data = try OllamaClient.encodeChatBody(request)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["think"])
    }

    func testThinkEncodedWhenSet() throws {
        let request = ChatRequest(model: "qwen", messages: [], contextSize: 4096, think: false)
        let data = try OllamaClient.encodeChatBody(request)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["think"] as? Bool, false)
    }

    // MARK: - ReasoningMode

    func testReasoningModeThinkMapping() {
        XCTAssertNil(ReasoningMode.auto.think)
        XCTAssertEqual(ReasoningMode.on.think, true)
        XCTAssertEqual(ReasoningMode.off.think, false)
    }

    func testReasoningModeRawRoundTrip() {
        for mode in ReasoningMode.allCases {
            XCTAssertEqual(ReasoningMode(rawValue: mode.rawValue), mode)
        }
    }

    func testSessionReasoningDefaultsToAuto() {
        XCTAssertEqual(ChatSession().reasoningMode, .auto)
    }

    func testSessionReasoningPersistsRaw() {
        let session = ChatSession()
        session.reasoningMode = .on
        XCTAssertEqual(session.reasoningRaw, ReasoningMode.on.rawValue)
    }
}

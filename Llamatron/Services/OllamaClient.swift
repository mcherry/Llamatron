import Foundation

/// Errors surfaced by the Ollama networking layer.
enum OllamaError: LocalizedError {
    case invalidURL
    case http(Int)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server address isn't a valid URL."
        case .http(let code):
            return "The server returned HTTP \(code)."
        case .server(let message):
            return message
        }
    }
}

/// The minimal capability the chat UI needs: stream a reply for a request. Both the
/// Ollama client and the Apple Foundation Models backend conform, so the view model
/// and views are backend-agnostic.
protocol ChatStreaming: Sendable {
    func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error>
}

/// Abstraction over a full Ollama-style backend. Refines `ChatStreaming` and adds the
/// server-only capabilities (model list, version) that Apple's on-device model lacks.
protocol LLMBackend: ChatStreaming {
    func version() async throws -> String
    func models() async throws -> [OllamaModel]
}

/// Talks to an Ollama server. A small `Sendable` value with no shared mutable
/// state, so it is safe to pass across actor boundaries.
struct OllamaClient: Sendable, LLMBackend {
    var baseURL: URL
    var timeout: TimeInterval

    /// Fails if `baseURLString` isn't a usable URL (no scheme/host), so callers can
    /// surface a clear "check Settings" message instead of silently doing nothing.
    init?(baseURLString: String, timeout: TimeInterval = 120) {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else { return nil }
        self.baseURL = url
        self.timeout = timeout
    }

    // MARK: Requests

    func version() async throws -> String {
        let data = try await get("api/version")
        return try JSONDecoder().decode(VersionResponse.self, from: data).version
    }

    func models() async throws -> [OllamaModel] {
        let data = try await get("api/tags")
        return try JSONDecoder().decode(TagsResponse.self, from: data).models
    }

    /// Models currently loaded in memory (`GET /api/ps`).
    func runningModels() async throws -> [RunningModel] {
        let data = try await get("api/ps")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PsResponse.self, from: data).models
            .map { RunningModel(name: $0.name, sizeVRAM: $0.sizeVram) }
    }

    /// Deletes a model from the server (`DELETE /api/delete`).
    func deleteModel(_ name: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "api/delete"))
        request.httpMethod = "DELETE"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["model": name])
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OllamaError.http(http.statusCode)
        }
    }

    /// Pulls a model, streaming progress updates (`POST /api/pull`, JSONL).
    func pullModel(_ name: String) -> AsyncThrowingStream<PullProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appending(path: "api/pull"))
                    request.httpMethod = "POST"
                    request.timeoutInterval = 3600
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(["model": name])

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        throw OllamaError.http(http.statusCode)
                    }
                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
                        let parsed = try decoder.decode(PullLine.self, from: data)
                        if let error = parsed.error { throw OllamaError.server(error) }
                        continuation.yield(PullProgress(status: parsed.status ?? "",
                                                        completed: parsed.completed,
                                                        total: parsed.total))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Batch-embeds `input` strings via `/api/embed`. Returns one vector per input,
    /// in order. Used by the retrieval (RAG) context strategy.
    func embed(model: String, input: [String]) async throws -> [[Float]] {
        guard !input.isEmpty else { return [] }
        var request = URLRequest(url: baseURL.appending(path: "api/embed"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(EmbedRequestBody(model: model, input: input))

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OllamaError.http(http.statusCode)
        }
        let vectors = try JSONDecoder().decode(EmbedResponse.self, from: data).embeddings
        guard vectors.count == input.count else {
            throw OllamaError.server("Embedding count mismatch (\(vectors.count) for \(input.count) inputs).")
        }
        return vectors
    }

    func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeChatRequest(request)
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        throw await Self.readError(from: bytes, status: http.statusCode)
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if let chunk = try Self.parseLine(line) {
                            continuation.yield(chunk)
                            if chunk.done { break }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Tear down the URLSession stream when the consumer stops (e.g. the user
            // taps Stop), so generation actually halts on the server.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Helpers

    private func get(_ path: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OllamaError.http(http.statusCode)
        }
        return data
    }

    private func makeChatRequest(_ request: ChatRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appending(path: "api/chat"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try Self.encodeChatBody(request)
        return urlRequest
    }

    /// Encodes a chat request into its JSON wire body. Pure and static so the exact
    /// payload (snake_cased keys, unset options omitted, seed for reproducibility) can
    /// be unit-tested without a server.
    static func encodeChatBody(_ request: ChatRequest) throws -> Data {
        let p = request.parameters
        let body = ChatRequestBody(
            model: request.model,
            messages: request.messages,
            stream: request.stream,
            think: request.think,
            options: .init(numCtx: request.contextSize,
                           numPredict: request.numPredict,
                           temperature: p.temperature,
                           topP: p.topP,
                           topK: p.topK,
                           repeatPenalty: p.repeatPenalty,
                           seed: p.seed,
                           stop: p.stop.isEmpty ? nil : p.stop)
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(body)
    }

    /// Drains the body of a failed response to recover Ollama's `{"error": ...}`
    /// message, falling back to the HTTP status code.
    private static func readError(from bytes: URLSession.AsyncBytes, status: Int) async -> OllamaError {
        var body = ""
        do {
            for try await line in bytes.lines { body += line }
        } catch {
            // Ignore; fall back to the status code below.
        }
        if let data = body.data(using: .utf8),
           let object = try? JSONDecoder().decode([String: String].self, from: data),
           let message = object["error"], !message.isEmpty {
            return .server(message)
        }
        return .http(status)
    }

    /// Decodes one line of the streamed JSONL response into a `ChatChunk`.
    /// Returns `nil` for blank lines and throws `OllamaError.server` for error
    /// payloads. Pure and synchronous so it can be unit-tested without a server.
    static func parseLine(_ line: String) throws -> ChatChunk? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let parsed = try decoder.decode(StreamLine.self, from: data)

        if let error = parsed.error {
            throw OllamaError.server(error)
        }
        return ChatChunk(
            contentDelta: parsed.message?.content ?? "",
            done: parsed.done ?? false,
            promptTokens: parsed.promptEvalCount,
            evalTokens: parsed.evalCount,
            evalDurationNanos: parsed.evalDuration,
            thinkingDelta: parsed.message?.thinking ?? "",
            doneReason: parsed.doneReason
        )
    }
}

// MARK: - Wire formats

private struct ChatRequestBody: Encodable {
    let model: String
    let messages: [ChatTurn]
    let stream: Bool
    /// Omitted when `nil` (synthesized `Encodable` skips nil optionals).
    let think: Bool?
    let options: Options

    struct Options: Encodable {
        let numCtx: Int
        let numPredict: Int?
        var temperature: Double?
        var topP: Double?
        var topK: Int?
        var repeatPenalty: Double?
        var seed: Int?
        var stop: [String]?
    }
}

private struct EmbedRequestBody: Encodable {
    let model: String
    let input: [String]
}

private struct EmbedResponse: Decodable {
    let embeddings: [[Float]]
}

private struct PullLine: Decodable {
    let status: String?
    let completed: Int?
    let total: Int?
    let error: String?
}

private struct StreamLine: Decodable {
    let message: Message?
    let done: Bool?
    let doneReason: String?
    let error: String?
    let promptEvalCount: Int?
    let evalCount: Int?
    let evalDuration: Int?

    struct Message: Decodable {
        let content: String?
        let thinking: String?
    }
}

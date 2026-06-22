import Foundation

// MARK: - Models list (/api/tags)

/// One model entry from `/api/tags`. `Sendable` so it can cross actor boundaries.
struct OllamaModel: Codable, Sendable, Identifiable, Hashable {
    let name: String
    let details: Details?
    let size: Int?

    var id: String { name }

    init(name: String, details: Details?, size: Int? = nil) {
        self.name = name
        self.details = details
        self.size = size
    }

    struct Details: Codable, Sendable, Hashable {
        let family: String?
        let families: [String]?
        let parameterSize: String?

        enum CodingKeys: String, CodingKey {
            case family
            case families
            case parameterSize = "parameter_size"
        }
    }

    /// Heuristic to keep embedding-only models (e.g. `nomic-embed-text`) out of the
    /// chat picker. `/api/tags` doesn't report capabilities, so we match on the name
    /// and model family, which covers the common embedding models.
    var isEmbeddingModel: Bool {
        var haystack = [name.lowercased(), (details?.family ?? "").lowercased()]
        haystack.append(contentsOf: (details?.families ?? []).map { $0.lowercased() })
        return haystack.contains { $0.contains("embed") }
    }

    /// Human-readable on-disk size, e.g. "18.6 GB".
    var sizeLabel: String? {
        guard let size else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

struct TagsResponse: Codable, Sendable {
    let models: [OllamaModel]
}

struct VersionResponse: Codable, Sendable {
    let version: String
}

// MARK: - Model management (/api/ps, /api/pull, /api/delete)

/// A currently-loaded model from `/api/ps`.
struct RunningModel: Sendable, Identifiable {
    let name: String
    let sizeVRAM: Int?
    var id: String { name }

    var vramLabel: String? {
        guard let sizeVRAM else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(sizeVRAM), countStyle: .file)
    }
}

struct PsResponse: Decodable, Sendable {
    let models: [Entry]
    struct Entry: Decodable, Sendable {
        let name: String
        let sizeVram: Int?
    }
}

/// One progress update while pulling a model (`/api/pull` streams JSONL).
struct PullProgress: Sendable {
    var status: String
    var completed: Int?
    var total: Int?

    /// Download fraction in `0...1` when byte counts are present.
    var fraction: Double? {
        guard let completed, let total, total > 0 else { return nil }
        return Double(completed) / Double(total)
    }
}

// MARK: - Chat (/api/chat)

/// Per-session control over a thinking model's reasoning (Ollama's `think` flag).
/// `auto` lets the model decide (deepseek-r1 reasons by default); `on` forces it
/// (errors on models that don't support thinking); `off` suppresses it.
enum ReasoningMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case auto
    case on
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Automatic"
        case .on: return "Always on"
        case .off: return "Off"
        }
    }

    /// The `think` value to send, or `nil` to omit (model default).
    var think: Bool? {
        switch self {
        case .auto: return nil
        case .on: return true
        case .off: return false
        }
    }
}

/// A single message in an outgoing chat request. Distinct from the SwiftData
/// `ChatMessage` model: this is a plain `Sendable` value, safe to pass to a
/// background task.
struct ChatTurn: Codable, Sendable {
    let role: String
    let content: String
}

/// Sampling/generation parameters for a chat request. Every field is optional so
/// only the ones the user sets are sent (others fall back to the server default). A
/// fixed `seed` makes Ollama output reproducible — the backbone of repeatable tests.
struct GenerationParameters: Sendable, Equatable {
    var temperature: Double?
    var topP: Double?
    var topK: Int?
    var repeatPenalty: Double?
    var seed: Int?
    var stop: [String]

    init(temperature: Double? = nil,
         topP: Double? = nil,
         topK: Int? = nil,
         repeatPenalty: Double? = nil,
         seed: Int? = nil,
         stop: [String] = []) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repeatPenalty = repeatPenalty
        self.seed = seed
        self.stop = stop
    }

    /// True when nothing is set, so the request carries only `num_ctx`/`num_predict`.
    var isEmpty: Bool {
        temperature == nil && topP == nil && topK == nil
            && repeatPenalty == nil && seed == nil && stop.isEmpty
    }
}

/// Everything needed to issue one chat request. A plain `Sendable` value type.
struct ChatRequest: Sendable {
    var model: String
    var messages: [ChatTurn]
    var contextSize: Int
    var stream: Bool
    var numPredict: Int?
    /// When set, toggles Ollama's reasoning. `false` asks thinking models to answer
    /// directly (used for title generation). Omitted from the request when `nil`.
    var think: Bool?
    /// Sampling parameters (temperature, seed, …). Empty by default.
    var parameters: GenerationParameters

    init(model: String,
         messages: [ChatTurn],
         contextSize: Int,
         stream: Bool = true,
         numPredict: Int? = nil,
         think: Bool? = nil,
         parameters: GenerationParameters = GenerationParameters()) {
        self.model = model
        self.messages = messages
        self.contextSize = contextSize
        self.stream = stream
        self.numPredict = numPredict
        self.think = think
        self.parameters = parameters
    }
}

/// One decoded delta from the streamed chat response.
struct ChatChunk: Sendable {
    var contentDelta: String
    var done: Bool
    var promptTokens: Int?
    var evalTokens: Int?
    var evalDurationNanos: Int?
    /// When true, `contentDelta` is the *entire* reply so far (a cumulative snapshot)
    /// and should replace the message body rather than append. Apple's Foundation
    /// Models stream works this way; Ollama streams incremental deltas (false).
    var isReplacement: Bool = false
    /// Incremental reasoning text from thinking models (Ollama's `message.thinking`).
    /// Accumulated separately from the answer.
    var thinkingDelta: String = ""
}

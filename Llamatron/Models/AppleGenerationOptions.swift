import Foundation

/// How Apple's on-device model picks tokens. Apple bundles into one choice what
/// Ollama splits across top-k/top-p, so the testbed exposes it as a single picker.
/// Plain Swift (no FoundationModels import) so it compiles on the macOS 15 target.
enum AppleSamplingMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Let Apple choose (the framework default).
    case automatic
    /// Always pick the most likely token — deterministic and reproducible.
    case greedy
    /// Sample from a fixed number of high-probability tokens.
    case topK
    /// Nucleus sampling: a variable set of tokens above a probability threshold.
    case topP

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .greedy: return "Greedy (deterministic)"
        case .topK: return "Top-K"
        case .topP: return "Top-P (nucleus)"
        }
    }

    /// Whether this mode accepts a seed (the random modes do; greedy/automatic don't).
    var usesSeed: Bool {
        self == .topK || self == .topP
    }
}

/// The subset of generation controls Apple's Foundation Models exposes. A plain
/// `Sendable` value passed to `FoundationModelsBackend`. Far smaller than Ollama's
/// set: no repeat penalty, no stop sequences, no context override.
struct AppleGenerationOptions: Sendable, Equatable {
    var temperature: Double?
    var maximumResponseTokens: Int?
    var samplingMode: AppleSamplingMode
    var topK: Int?
    var topP: Double?
    var seed: Int?

    init(temperature: Double? = nil,
         maximumResponseTokens: Int? = nil,
         samplingMode: AppleSamplingMode = .automatic,
         topK: Int? = nil,
         topP: Double? = nil,
         seed: Int? = nil) {
        self.temperature = temperature
        self.maximumResponseTokens = maximumResponseTokens
        self.samplingMode = samplingMode
        self.topK = topK
        self.topP = topP
        self.seed = seed
    }

    /// True when everything is at its default (nothing overridden).
    var isEmpty: Bool {
        temperature == nil
            && maximumResponseTokens == nil
            && samplingMode == .automatic
            && seed == nil
    }
}

import Foundation

/// A model offered by an image-generation server, for the Settings picker.
struct ImageModel: Identifiable, Hashable, Sendable {
    /// Stable identifier the server expects (e.g. `"sd-v1-5"`).
    let id: String
    /// Human-facing name (often the same as `id`).
    var name: String
}

/// A single image request: the resolved prompt plus the parameters chosen in Settings.
struct ImageRequest: Sendable {
    var prompt: String
    var negativePrompt: String
    var model: String
    var steps: Int
    var width: Int
    var height: Int
    /// Prompt-adherence strength (Stable Diffusion CFG/guidance). Higher = stronger style adherence.
    var cfgScale: Double
    /// VAE model name to apply, or empty for the model's built-in VAE.
    var vae: String
    /// Fixed seed for reproducibility, or `nil` for a fresh random one each time.
    var seed: Int?
}

/// Errors surfaced by the image-generation layer.
enum ImageGenError: LocalizedError {
    case invalidURL
    case http(Int)
    case noModelSelected
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The image server address isn't a valid URL."
        case .http(let code): return "The image server returned HTTP \(code)."
        case .noModelSelected: return "Pick an image model in Settings first."
        case .failed(let message): return message
        }
    }
}

/// A local image-generation backend. New servers are added by writing another conforming type and
/// an `ImageBackendKind` case — there is no user-facing way to register backends. `listModels()`
/// powers the Settings Test + model picker; `generate()` returns the rendered image bytes.
protocol ImageProvider: Sendable {
    func listModels() async throws -> [ImageModel]
    func listVAEs() async throws -> [ImageModel]
    func generate(_ request: ImageRequest) async throws -> Data
}

extension ImageProvider {
    /// Backends without separate VAEs report none.
    func listVAEs() async throws -> [ImageModel] { [] }
}

/// Gating + config helpers for the optional image-generation feature.
enum ImageGen {
    /// The single gate every "Generate" affordance checks: enabled, with a non-empty server URL.
    /// (Generation additionally needs a selected model; that's reported as a clear error at call time.)
    static func isConfigured(enabled: Bool, serverURL: String) -> Bool {
        enabled && !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Parses a `"WIDTHxHEIGHT"` size string (e.g. `"768x512"`) used by the image-size pickers.
enum ImageDimensions {
    /// Two positive integers separated by `x` (case-insensitive), else `nil`.
    static func parse(_ raw: String) -> (width: Int, height: Int)? {
        let parts = raw.split(whereSeparator: { $0 == "x" || $0 == "X" })
        guard parts.count == 2,
              let w = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let h = Int(parts[1].trimmingCharacters(in: .whitespaces)),
              w > 0, h > 0 else { return nil }
        return (w, h)
    }
}

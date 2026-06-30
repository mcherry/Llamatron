import Foundation

/// `@AppStorage` keys for app-wide settings, kept in one place to avoid typos.
enum SettingsKey {
    static let serverURL = "serverURL"
    static let defaultContextSize = "defaultContextSize"
    static let defaultModel = "defaultModel"
    static let requestTimeout = "requestTimeout"
    static let didCompleteFirstRun = "didCompleteFirstRun"
    static let composerHeight = "composerHeight"
    static let embeddingModel = "embeddingModel"
    static let diagramGuidance = "diagramGuidance"

    // Web search providers (used by the web-source search sheet).
    static let searchProvider = "searchProvider"
    static let searxngURL = "searxngURL"
    static let braveAPIKey = "braveAPIKey"
    static let tavilyAPIKey = "tavilyAPIKey"
    static let marginaliaAPIKey = "marginaliaAPIKey"
}

/// Default values for the settings above.
enum SettingsDefault {
    static let serverURL = "http://localhost:11434"
    static let contextSize = 32768
    static let timeout = 120
    static let composerHeight = 72.0
    static let embeddingModel = "nomic-embed-text"
}

/// Context-window presets offered in the pickers, plus a display formatter.
enum ContextSize {
    /// Common `num_ctx` values. The high end (256K–1M) suits long-context models on
    /// beefier servers; the model/server clamps anything it can't actually support.
    static let presets = [4096, 8192, 16384, 32768, 65536, 131072, 262144, 524288, 1048576]

    static func label(_ n: Int) -> String {
        if n >= 1_048_576 && n % 1_048_576 == 0 { return "\(n / 1_048_576)M" }
        if n >= 1024 && n % 1024 == 0 { return "\(n / 1024)K" }
        return "\(n)"
    }
}

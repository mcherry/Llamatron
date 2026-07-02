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
    /// Right-size `num_ctx` to each request instead of always sending the full window.
    static let rightSizeContext = "rightSizeContext"
    /// How long Ollama keeps the model loaded between turns, in minutes.
    static let keepAliveMinutes = "keepAliveMinutes"

    // Web search providers (used by the web-source search sheet).
    static let searchProvider = "searchProvider"
    static let searxngURL = "searxngURL"
    static let braveAPIKey = "braveAPIKey"
    static let tavilyAPIKey = "tavilyAPIKey"
    static let marginaliaAPIKey = "marginaliaAPIKey"

    // Image generation (app defaults; per-chat overrides live on ChatSession).
    static let imageGenEnabled = "imageGenEnabled"
    static let imageBackendKind = "imageBackendKind"
    static let imageServerURL = "imageServerURL"
    static let imageModel = "imageModel"
    static let imageSteps = "imageSteps"
    static let imageSize = "imageSize"
    static let imageCFG = "imageCFG"
    static let imageNegativePrompt = "imageNegativePrompt"

    // Text-to-speech (app-level engine config; per-chat enable/engine live on ChatSession).
    static let ttsEngine = "ttsEngine"
    static let ttsAppleVoice = "ttsAppleVoice"
    static let ttsServerURL = "ttsServerURL"
    static let ttsVoice = "ttsVoice"
    static let ttsSpeed = "ttsSpeed"

    // Speech-to-text dictation (on-device; fills the composer).
    static let dictationAutoSend = "dictationAutoSend"
    static let dictationPauseSeconds = "dictationPauseSeconds"
    /// Opt-in always-on, hands-free back-and-forth dictation.
    static let conversationMode = "conversationMode"
    /// Apple voice processing (noise suppression + echo cancellation) for the mic.
    static let dictationVoiceProcessing = "dictationVoiceProcessing"
}

/// Default values for the settings above.
enum SettingsDefault {
    static let serverURL = "http://localhost:11434"
    static let contextSize = 32768
    static let timeout = 120
    static let composerHeight = 72.0
    static let embeddingModel = "nomic-embed-text"
    static let rightSizeContext = true
    static let keepAliveMinutes = 5
    static let imageServerURL = "http://localhost:9000"
    static let imageSteps = 20
    static let imageSize = 640
    static let imageCFG = 7.5
    static let ttsServerURL = "http://localhost:8880"
    static let ttsSpeed = 1.0
    static let dictationPauseSeconds = 1.5
    static let dictationVoiceProcessing = true
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

    /// The smallest preset window that holds `needed` tokens without exceeding
    /// `ceiling` (the user's chosen size, itself capped to the model's real limit).
    /// Snapping to presets keeps `num_ctx` stable across similar turns so Ollama's
    /// prompt cache stays warm, while still sending only as much window as the request
    /// actually needs — less KV-cache memory and faster loads on modest hardware.
    static func rightSized(needed: Int, ceiling: Int) -> Int {
        let cap = max(1, ceiling)
        let n = max(1, needed)
        if n >= cap { return cap }
        if let preset = presets.first(where: { $0 >= n && $0 <= cap }) { return preset }
        return cap
    }
}

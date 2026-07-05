import Foundation
import LlamaEngine
import LlamaEngineStore

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
    /// The ComfyUI workflow-template library, stored as JSON (see `ComfyTemplateLibrary`).
    static let comfyTemplates = "comfyTemplates"

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

/// The app-side library of ComfyUI workflow templates, persisted as a JSON string in
/// `@AppStorage(SettingsKey.comfyTemplates)`. A small shared codec so Settings (manage) and
/// Session config (pick) agree on the storage format. Templates are `Codable` in the engine.
enum ComfyTemplateLibrary {
    /// Decodes the stored library JSON, tolerating an empty or damaged value (→ `[]`).
    static func decode(_ json: String) -> [ComfyWorkflowTemplate] {
        guard let data = json.data(using: .utf8),
              let templates = try? JSONDecoder().decode([ComfyWorkflowTemplate].self, from: data)
        else { return [] }
        return templates
    }

    /// Encodes a library to a JSON string suitable for `@AppStorage`.
    static func encode(_ templates: [ComfyWorkflowTemplate]) -> String {
        guard let data = try? JSONEncoder().encode(templates),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    /// The template whose id (its `UUID` string) matches `id`, from a stored library JSON.
    static func template(id: String, in json: String) -> ComfyWorkflowTemplate? {
        guard !id.isEmpty else { return nil }
        return decode(json).first { $0.id.uuidString == id }
    }
}

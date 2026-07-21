import Foundation
import LlamaEngine
import LlamaEngineStore

/// Meta-search membership, derived from the persisted CSV of *disabled* provider rawValues
/// so the default (empty string) enables every provider in the catalog.
enum WebSearchSettings {
    static func enabledProviders(disabledCSV: String) -> Set<WebSearch.ProviderKind> {
        let disabled = Set(disabledCSV.split(separator: ",").map(String.init))
        return Set(WebSearch.catalog.filter { !disabled.contains($0.rawValue) })
    }
}

/// `@AppStorage` keys for app-wide settings, kept in one place to avoid typos.
enum SettingsKey {
    static let serverURL = "serverURL"
    /// Base URL of a llama.cpp `llama-server` (OpenAI-compatible API), used by
    /// llama.cpp-backend sessions.
    static let llamaServerURL = "llamaServerURL"
    static let defaultContextSize = "defaultContextSize"
    static let defaultModel = "defaultModel"
    /// Which backend a new session starts with.
    static let defaultBackend = "defaultBackend"
    static let requestTimeout = "requestTimeout"
    static let didCompleteFirstRun = "didCompleteFirstRun"
    static let composerHeight = "composerHeight"
    static let diagramGuidance = "diagramGuidance"
    /// Right-size `num_ctx` to each request instead of always sending the full window.
    static let rightSizeContext = "rightSizeContext"
    /// How long Ollama keeps the model loaded between turns, in minutes.
    static let keepAliveMinutes = "keepAliveMinutes"

    // Optional feature modules (master on/off). Image generation uses `imageGenEnabled`.
    static let ttsFeatureEnabled = "ttsFeatureEnabled"
    static let sttFeatureEnabled = "sttFeatureEnabled"
    static let webSearchEnabled = "webSearchEnabled"

    // Web search providers (used by the web-source search sheet).
    static let searchProvider = "searchProvider"
    static let searxngURL = "searxngURL"
    static let braveAPIKey = "braveAPIKey"
    static let tavilyAPIKey = "tavilyAPIKey"
    static let exaAPIKey = "exaAPIKey"
    static let linkupAPIKey = "linkupAPIKey"
    static let tinyfishAPIKey = "tinyfishAPIKey"
    static let marginaliaAPIKey = "marginaliaAPIKey"
    /// Meta-search: providers excluded from the fan-out, as a CSV of provider rawValues
    /// (empty = every provider enabled).
    static let metaDisabledProviders = "metaDisabledProviders"

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
    /// Saved session presets (full per-chat configurations), JSON-encoded.
    static let sessionPresets = "sessionPresets"
    /// The id of the preset new chats start from; empty = the App defaults below.
    static let defaultPresetID = "defaultPresetID"

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
    static let llamaServerURL = "http://localhost:8080"
    static let defaultBackend = BackendKind.ollama.rawValue
    static let contextSize = 32768
    static let timeout = 120
    static let composerHeight = 72.0
    static let rightSizeContext = true
    static let keepAliveMinutes = 5
    static let ttsFeatureEnabled = true
    static let sttFeatureEnabled = true
    static let webSearchEnabled = true
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

/// The app-side library of session presets (full per-chat configurations), persisted as a
/// JSON string in `@AppStorage(SettingsKey.sessionPresets)`. Mirrors `ComfyTemplateLibrary`;
/// the `SessionPreset` / `SessionConfig` value types live in the engine store.
enum SessionPresetLibrary {
    /// Decodes the stored library JSON, tolerating an empty or damaged value (→ `[]`).
    static func decode(_ json: String) -> [SessionPreset] {
        guard let data = json.data(using: .utf8),
              let presets = try? JSONDecoder().decode([SessionPreset].self, from: data)
        else { return [] }
        return presets
    }

    /// Encodes a library to a JSON string suitable for `@AppStorage`.
    static func encode(_ presets: [SessionPreset]) -> String {
        guard let data = try? JSONEncoder().encode(presets),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    /// The preset whose id matches `id`, from a stored library JSON.
    static func preset(id: String, in json: String) -> SessionPreset? {
        guard !id.isEmpty else { return nil }
        return decode(json).first { $0.id == id }
    }
}

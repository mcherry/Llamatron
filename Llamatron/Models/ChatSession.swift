import Foundation
import LlamaEngine
import SwiftData

/// A saved conversation plus its per-session configuration: which model to use,
/// the context size, and the system prompt. Auto-saves via SwiftData and reappears
/// on relaunch. Deleting a session cascades to its messages.
@Model
final class ChatSession {
    var id: UUID = UUID()
    var title: String = "New Session"
    /// The Ollama model name this session talks to (e.g. "qwen-14b").
    var modelName: String = ""
    /// Per-session context window (`num_ctx`) sent with each request.
    var contextSize: Int = 32768
    /// The system prompt sent as the leading `system` message.
    var systemPrompt: String = ""
    var createdAt: Date = Date.now
    /// Bumped when a turn completes, so the sidebar sorts most-recent first.
    var updatedAt: Date = Date.now
    /// True while the title is auto-generated. Set false once the user renames it,
    /// so auto-naming stops overwriting their choice.
    var titleIsAuto: Bool = true
    /// How attached files are fitted into the prompt. See `ContextMode`.
    var contextModeRaw: String = ContextMode.auto.rawValue
    /// Which engine answers this session. See `BackendKind`.
    var backendRaw: String = BackendKind.ollama.rawValue

    // Generation parameters (Ollama). Each is optional: nil means "use the server
    // default". A fixed `seed` makes output reproducible across runs.
    var temperature: Double?
    var topP: Double?
    var topK: Int?
    var repeatPenalty: Double?
    var seed: Int?
    var stopSequences: [String] = []

    // Apple Intelligence generation controls (reuses temperature/topK/topP/seed above).
    var maxResponseTokens: Int?
    var appleSamplingRaw: String = AppleSamplingMode.automatic.rawValue
    /// How to handle reasoning for thinking models (Ollama `think`). See `ReasoningMode`.
    var reasoningRaw: String = ReasoningMode.auto.rawValue
    /// How conversation history is fitted into the window. See `HistoryMode`.
    var historyModeRaw: String = HistoryMode.full.rawValue
    /// Cached rolling summary of older turns (for `.summarize` history mode).
    var historySummary: String = ""
    /// `createdAt` of the newest message already folded into `historySummary`.
    var summarizedUntil: Date?
    /// Vision model used to describe attached images before sending to the primary
    /// model (the multi-model "eyes" pipeline). Empty = no dedicated vision model;
    /// images then go natively to the primary model if it supports vision.
    var visionModel: String = ""

    // Image generation (when `backend == .imageGeneration`). The server URL + kind are
    // app-level (Settings); these are the per-chat model and parameters.
    var imageModel: String = ""
    var imageSize: Int = 640
    var imageSteps: Int = 20
    var imageCFG: Double = 7.5
    var imageNegativePrompt: String = ""
    var imageSeed: Int?
    var imageVAE: String = ""

    // Text-to-speech (per chat). Voices/speed are app-level (Settings).
    var ttsEnabled: Bool = false
    var ttsEngineRaw: String = TTSEngine.apple.rawValue
    var ttsAutoSpeak: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.session)
    var messages: [ChatMessage] = []

    @Relationship(deleteRule: .cascade, inverse: \Attachment.session)
    var attachments: [Attachment] = []

    init(title: String = "New Session",
         modelName: String = "",
         contextSize: Int = 32768,
         systemPrompt: String = "") {
        self.id = UUID()
        self.title = title
        self.modelName = modelName
        self.contextSize = contextSize
        self.systemPrompt = systemPrompt
        self.createdAt = .now
        self.updatedAt = .now
        self.titleIsAuto = true
        self.contextModeRaw = ContextMode.auto.rawValue
        self.backendRaw = BackendKind.ollama.rawValue
    }

    /// Typed accessor over `contextModeRaw`.
    var contextMode: ContextMode {
        get { ContextMode(rawValue: contextModeRaw) ?? .auto }
        set { contextModeRaw = newValue.rawValue }
    }

    /// Typed accessor over `backendRaw`.
    var backend: BackendKind {
        get { BackendKind(rawValue: backendRaw) ?? .ollama }
        set { backendRaw = newValue.rawValue }
    }

    /// Typed accessor over `historyModeRaw`.
    var historyMode: HistoryMode {
        get { HistoryMode(rawValue: historyModeRaw) ?? .full }
        set { historyModeRaw = newValue.rawValue }
    }

    /// Typed accessor over `ttsEngineRaw`.
    var ttsEngine: TTSEngine {
        get { TTSEngine(rawValue: ttsEngineRaw) ?? .apple }
        set { ttsEngineRaw = newValue.rawValue }
    }

    /// The session's sampling parameters as a plain `Sendable` value for requests.
    var generationParameters: GenerationParameters {
        GenerationParameters(temperature: temperature,
                             topP: topP,
                             topK: topK,
                             repeatPenalty: repeatPenalty,
                             seed: seed,
                             stop: stopSequences)
    }

    /// Typed accessor over `appleSamplingRaw`.
    var appleSamplingMode: AppleSamplingMode {
        get { AppleSamplingMode(rawValue: appleSamplingRaw) ?? .automatic }
        set { appleSamplingRaw = newValue.rawValue }
    }

    /// Typed accessor over `reasoningRaw`.
    var reasoningMode: ReasoningMode {
        get { ReasoningMode(rawValue: reasoningRaw) ?? .auto }
        set { reasoningRaw = newValue.rawValue }
    }

    /// The session's Apple Intelligence generation controls as a `Sendable` value.
    var appleOptions: AppleGenerationOptions {
        AppleGenerationOptions(temperature: temperature,
                               maximumResponseTokens: maxResponseTokens,
                               samplingMode: appleSamplingMode,
                               topK: topK,
                               topP: topP,
                               seed: seed)
    }

    /// Whether the session has enough configuration to send. Ollama needs a chosen
    /// model; Apple Intelligence has a single on-device model, so it's always ready.
    var isConfigured: Bool {
        switch backend {
        case .ollama: return !modelName.isEmpty
        case .appleIntelligence: return true
        case .imageGeneration: return !imageModel.isEmpty
        }
    }

    /// Messages in chronological order for display.
    var orderedMessages: [ChatMessage] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }

    /// Attachments oldest-first, for stable context ordering and display.
    var orderedAttachments: [Attachment] {
        attachments.sorted { $0.createdAt < $1.createdAt }
    }
}

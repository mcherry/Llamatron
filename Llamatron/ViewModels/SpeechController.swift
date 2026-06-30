import AVFoundation
import Observation

/// Drives text-to-speech playback for the chat: either Apple's on-device synthesizer or a
/// Kokoro server (fetched off-main, then played via `AVAudioPlayer`). `@MainActor` so the
/// observable `speakingMessageID` updates the UI directly; only one message speaks at a time.
@MainActor
@Observable
final class SpeechController: NSObject {
    /// The id of the message currently being spoken, or `nil` when idle.
    private(set) var speakingMessageID: UUID?
    /// The id of the message whose audio is being saved, or `nil` when not saving.
    private(set) var savingMessageID: UUID?
    /// Set when a save fails, for the UI to surface (and clear).
    var saveError: String?

    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var fetchTask: Task<Void, Never>?

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Resolved engine + voice/speed settings for one speak request.
    struct Config: Sendable {
        var engine: TTSEngine
        var appleVoice: String
        var serverURL: String
        var serverVoice: String
        var speed: Double
    }

    /// Speaks `text` for `messageID`, or stops if that message is already speaking.
    func toggle(messageID: UUID, text: String, config: Config) {
        if speakingMessageID == messageID { stop() } else { speak(messageID: messageID, text: text, config: config) }
    }

    /// Starts speaking `text` (stopping anything already playing).
    func speak(messageID: UUID, text: String, config: Config) {
        stop()
        let spoken = TextForSpeech.plain(text)
        guard !spoken.isEmpty else { return }
        speakingMessageID = messageID

        switch config.engine {
        case .apple:
            let utterance = AVSpeechUtterance(string: spoken)
            if !config.appleVoice.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: config.appleVoice) {
                utterance.voice = voice
            }
            utterance.rate = Self.appleRate(for: config.speed)
            synth.speak(utterance)
        case .server:
            let provider = KokoroTTSProvider(baseURLString: config.serverURL)
            let request = TTSRequest(text: spoken, voice: config.serverVoice, speed: config.speed, format: "wav")
            fetchTask = Task { [weak self] in
                let data = try? await provider.synthesize(request)
                guard let self, self.speakingMessageID == messageID else { return }
                guard let data, let player = try? AVAudioPlayer(data: data) else {
                    self.speakingMessageID = nil
                    return
                }
                player.delegate = self
                self.player = player
                player.play()
            }
        }
    }

    /// Renders `text` to a single AAC `.m4a` at `url` (Apple on-device or the Kokoro server).
    func saveAudio(messageID: UUID, text: String, config: Config, to url: URL) {
        guard savingMessageID == nil else { return }
        let spoken = TextForSpeech.plain(text)
        guard !spoken.isEmpty else { return }
        savingMessageID = messageID
        Task { [weak self] in
            do {
                switch config.engine {
                case .apple:
                    try await AudioExport.writeM4A(appleText: spoken, voice: config.appleVoice,
                                                   speed: config.speed, to: url)
                case .server:
                    let provider = KokoroTTSProvider(baseURLString: config.serverURL)
                    let data = try await provider.synthesize(
                        TTSRequest(text: spoken, voice: config.serverVoice, speed: config.speed, format: "wav"))
                    try await Task.detached { try AudioExport.writeM4A(wav: data, to: url) }.value
                }
            } catch {
                self?.saveError = error.localizedDescription
            }
            self?.savingMessageID = nil
        }
    }

    /// Stops any in-progress speech and clears the speaking state.
    func stop() {
        fetchTask?.cancel()
        fetchTask = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player?.stop()
        player = nil
        speakingMessageID = nil
    }

    /// Maps a 0.5–2.0 "speed" onto `AVSpeechUtterance.rate` around the platform default.
    nonisolated static func appleRate(for speed: Double) -> Float {
        let rate = AVSpeechUtteranceDefaultSpeechRate * Float(speed)
        return min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }
}

extension SpeechController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.speakingMessageID = nil }
    }
}

extension SpeechController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.speakingMessageID = nil }
    }
}

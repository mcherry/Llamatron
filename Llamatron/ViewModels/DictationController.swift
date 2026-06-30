import AVFoundation
import Observation
import Speech

/// Drives speech-to-text dictation for the composer: streams microphone audio through
/// `SFSpeechRecognizer` (on-device when supported) and publishes a live `transcript`.
/// `@MainActor` so its observable state updates the UI directly; recognition callbacks
/// hop back to the main actor with only `Sendable` values.
///
/// Submission is the caller's job: the live transcript flows into the draft, and the
/// user sends manually. When `autoSend` is on, a pause in speech bumps `autoSendTick`
/// so the view can submit hands-free.
@MainActor
@Observable
final class DictationController {
    /// True while the microphone is open and transcribing.
    private(set) var isListening = false
    /// The best transcription so far for the current dictation session.
    private(set) var transcript = ""
    /// Set when dictation can't start or fails, for the UI to surface (and clear).
    var errorMessage: String?
    /// Incremented when a speech pause should auto-submit (only when `autoSend` is on).
    /// The view observes this and sends the draft.
    private(set) var autoSendTick = 0

    /// When true, a pause longer than `silenceSeconds` ends dictation and requests a send.
    var autoSend = false
    /// Silence (no new words) that counts as "done speaking" for auto-send.
    var silenceSeconds: Double = 1.5

    /// Whether speech recognition is usable at all (a recognizer exists for the locale).
    var isSupported: Bool { recognizer != nil }

    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var starting = false

    /// Starts dictation if idle, otherwise stops it.
    func toggle() {
        if isListening || starting { stop() } else { start() }
    }

    /// Requests permission (first run) and begins streaming microphone audio.
    func start() {
        guard !isListening, !starting else { return }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available on this Mac."
            return
        }
        starting = true
        transcript = ""
        errorMessage = nil
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard status == .authorized else {
                    self.starting = false
                    self.errorMessage = "Allow speech recognition in System Settings ▸ Privacy to dictate."
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard granted else {
                            self.starting = false
                            self.errorMessage = "Allow microphone access in System Settings ▸ Privacy to dictate."
                            return
                        }
                        self.beginSession()
                    }
                }
            }
        }
    }

    private func beginSession() {
        guard let recognizer else { starting = false; return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep audio on-device when the Mac supports it (privacy + offline).
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            // Runs on the audio thread; `append` is safe to call there.
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            starting = false
            errorMessage = error.localizedDescription
            teardown()
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Extract only Sendable values before hopping to the main actor.
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in
                self?.handle(text: text, isFinal: isFinal, failed: failed)
            }
        }

        starting = false
        isListening = true
        if autoSend { restartSilenceTimer() }
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        guard isListening else { return }
        if let text {
            transcript = text
            if autoSend { restartSilenceTimer() }
        }
        if isFinal {
            // The recognizer ended the utterance on its own.
            if autoSend && !transcript.isEmpty {
                autoSendTick &+= 1
            }
            stop()
        } else if failed {
            stop()
        }
    }

    /// Restarts the "stopped speaking" countdown; firing it auto-submits.
    private func restartSilenceTimer() {
        silenceTask?.cancel()
        let seconds = max(0.3, silenceSeconds)
        silenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.isListening, !self.transcript.isEmpty else { return }
                self.autoSendTick &+= 1
                self.stop()
            }
        }
    }

    /// Stops dictation and releases the microphone. The transcript stays in the draft.
    func stop() {
        guard isListening || starting else { return }
        silenceTask?.cancel()
        silenceTask = nil
        task?.cancel()
        task = nil
        teardown()
        starting = false
        isListening = false
    }

    /// Tears down the audio engine and recognition request.
    private func teardown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
    }

    func clearError() { errorMessage = nil }

    /// Combines existing draft text with a live transcript: the transcript is appended
    /// after the draft (with a single separating space), so dictation adds to whatever
    /// the user already typed.
    nonisolated static func composed(base: String, transcript: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBase.isEmpty { return transcript }
        if transcript.isEmpty { return trimmedBase }
        return trimmedBase + " " + transcript
    }
}

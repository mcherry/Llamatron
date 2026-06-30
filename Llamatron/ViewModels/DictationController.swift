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
    private var engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var sink: AudioSink?
    private var task: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var starting = false

    /// Starts dictation if idle, otherwise stops it.
    func toggle() {
        if isListening || starting { stop() } else { start() }
    }

    /// Requests permission (first run) and begins streaming microphone audio. All work
    /// stays on the main actor — the engine and recognizer are set up from one consistent
    /// queue, which the audio frameworks expect.
    func start() {
        guard !isListening, !starting else { return }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available on this Mac."
            return
        }
        starting = true
        transcript = ""
        errorMessage = nil
        Task { @MainActor in
            let speechStatus = await Self.requestSpeechAuthorization()
            guard !Task.isCancelled, starting else { return }
            guard speechStatus == .authorized else {
                starting = false
                errorMessage = "Allow speech recognition in System Settings ▸ Privacy & Security to dictate."
                return
            }
            let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
            guard !Task.isCancelled, starting else { return }
            guard micGranted else {
                starting = false
                errorMessage = "Allow microphone access in System Settings ▸ Privacy & Security to dictate."
                return
            }
            beginSession()
        }
    }

    /// Async wrapper over the callback-based speech authorization request.
    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func beginSession() {
        guard let recognizer else { starting = false; return }
        // A fresh engine each session avoids stale CoreAudio state from a prior run.
        engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // On the first run the HAL may not be ready the instant permission is granted;
        // a zero-channel/zero-rate format would crash `installTap`/`start`.
        guard format.channelCount > 0, format.sampleRate > 0 else {
            starting = false
            errorMessage = "The microphone isn't ready yet. Try the mic again."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep audio on-device when the Mac supports it (privacy + offline).
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        let sink = AudioSink(request)
        self.sink = sink

        // Start recognition before wiring the microphone, matching Apple's pattern.
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Extract only Sendable values before hopping to the main actor.
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in
                self?.handle(text: text, isFinal: isFinal, failed: failed)
            }
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            // Runs on the audio thread; the sink guards against appending after the
            // request has been ended (which would crash).
            sink.append(buffer)
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
            // Surface why only if nothing was transcribed (the common cause is that
            // Dictation is turned off system-wide, which disables recognition).
            if transcript.isEmpty {
                errorMessage = "Couldn't start speech recognition. Turn on Dictation in System Settings ▸ Keyboard, then try again."
            }
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
        sink?.finish()
        sink = nil
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

/// A thread-safe bridge from the real-time audio tap to the recognition request. The tap
/// runs on the audio I/O thread while teardown happens on the main actor; the lock ensures
/// a buffer is never appended after `finish()` has ended the request (which would crash).
private final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }

    func finish() {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio()
        request = nil
    }
}

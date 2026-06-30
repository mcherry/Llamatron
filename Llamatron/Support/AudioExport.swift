import AVFoundation

/// Encodes speech to a single canonical format — **AAC in an `.m4a`** — so saved audio is
/// consistent regardless of engine and stays small. The Kokoro server returns WAV which we
/// transcode; the Apple synthesizer streams PCM buffers we convert and encode. Apple has no
/// MP3 *encoder*, so `.m4a` (AAC) is the small, dependency-free choice.
enum AudioExport {
    enum ExportError: LocalizedError {
        case noAudio
        case encodeFailed
        var errorDescription: String? {
            switch self {
            case .noAudio: return "There was no audio to save."
            case .encodeFailed: return "Couldn't encode the audio."
            }
        }
    }

    /// AAC bit rate for saved speech — ample for voice, still compact.
    private static let bitRate = 96_000

    /// Transcodes WAV/PCM `data` (from the Kokoro server) to an AAC `.m4a` at `url`.
    static func writeM4A(wav data: Data, to url: URL) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let input = try AVAudioFile(forReading: tmp)
        let format = input.processingFormat
        let frames = AVAudioFrameCount(input.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw ExportError.noAudio
        }
        try input.read(into: buffer)

        let output = try AVAudioFile(forWriting: url, settings: aacSettings(sampleRate: format.sampleRate,
                                                                            channels: format.channelCount))
        // The reader and writer both use a float processing format at the same rate/channels.
        try output.write(from: buffer)
    }

    /// Renders `text` with the on-device synthesizer and writes an AAC `.m4a` at `url`.
    static func writeM4A(appleText text: String, voice: String, speed: Double, to url: URL) async throws {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        if !voice.isEmpty, let v = AVSpeechSynthesisVoice(identifier: voice) { utterance.voice = v }
        utterance.rate = SpeechController.appleRate(for: speed)

        let writer = AACFileWriter(url: url)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                writer.handle(pcm, continuation: continuation)
            }
        }
        // Keep the synthesizer alive until the streamed write has finished.
        withExtendedLifetime(synthesizer) {}
    }

    static func aacSettings(sampleRate: Double, channels: AVAudioChannelCount) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitRate
        ]
    }
}

/// Accumulates the synthesizer's streamed PCM buffers into one AAC `.m4a` file, converting
/// each buffer to the file's float processing format. Resumes the continuation when the synth
/// signals the end (an empty buffer) or on the first error. The synth invokes its callback
/// serially on one thread, so the unchecked-`Sendable` state is touched from only that thread.
private final class AACFileWriter: @unchecked Sendable {
    private let url: URL
    private var output: AVAudioFile?
    private var converter: AVAudioConverter?
    private var finished = false

    init(url: URL) { self.url = url }

    func handle(_ pcm: AVAudioPCMBuffer, continuation: CheckedContinuation<Void, Error>) {
        guard !finished else { return }
        if pcm.frameLength == 0 {
            finished = true
            if output == nil {
                continuation.resume(throwing: AudioExport.ExportError.noAudio)
            } else {
                continuation.resume()
            }
            return
        }
        do {
            try append(pcm)
        } catch {
            finished = true
            continuation.resume(throwing: error)
        }
    }

    private func append(_ pcm: AVAudioPCMBuffer) throws {
        if output == nil {
            output = try AVAudioFile(forWriting: url,
                                     settings: AudioExport.aacSettings(sampleRate: pcm.format.sampleRate,
                                                                       channels: pcm.format.channelCount))
        }
        guard let output else { return }

        if pcm.format == output.processingFormat {
            try output.write(from: pcm)
            return
        }
        // Convert the synth's PCM (often Int16) to the file's float format. Same sample rate,
        // so the simple one-shot convert is sufficient.
        if converter == nil {
            converter = AVAudioConverter(from: pcm.format, to: output.processingFormat)
        }
        guard let converter,
              let converted = AVAudioPCMBuffer(pcmFormat: output.processingFormat,
                                               frameCapacity: pcm.frameLength) else {
            throw AudioExport.ExportError.encodeFailed
        }
        try converter.convert(to: converted, from: pcm)
        try output.write(from: converted)
    }
}

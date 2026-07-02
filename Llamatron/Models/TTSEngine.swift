import Foundation
import LlamaEngine

/// Which engine speaks a chat's replies. `apple` is the on-device synthesizer (no
/// server, no setup); `server` is a local Kokoro TTS server. Stored on `ChatSession`
/// as a raw string, like `BackendKind`.
enum TTSEngine: String, Codable, Sendable, CaseIterable, Identifiable {
    case apple
    case server

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple: return "Apple (on-device)"
        case .server: return "Kokoro server"
        }
    }
}

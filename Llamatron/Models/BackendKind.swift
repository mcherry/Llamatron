import Foundation

/// Which engine a session talks to. `ollama` is a remote Ollama server; `appleIntelligence`
/// is Apple's on-device Foundation Models (macOS 26+, only when enabled on the system).
/// Stored on `ChatSession` as a raw string for SwiftData simplicity.
enum BackendKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case ollama
    case appleIntelligence

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ollama: return "Ollama"
        case .appleIntelligence: return "Apple Intelligence"
        }
    }

    var systemImage: String {
        switch self {
        case .ollama: return "server.rack"
        case .appleIntelligence: return "apple.logo"
        }
    }
}

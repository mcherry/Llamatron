import Foundation

/// The role of a chat turn. Stored on `ChatMessage` as a raw string for SwiftData
/// simplicity and mapped to this enum in code.
enum Role: String, Codable, Sendable, CaseIterable {
    case system
    case user
    case assistant
}

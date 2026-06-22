import Foundation
import SwiftData

/// A saved, reusable system prompt for the prompt library. Users save the current
/// session's system prompt as a named preset and apply it to any session.
@Model
final class PromptPreset {
    var id: UUID = UUID()
    var name: String = ""
    var content: String = ""
    var createdAt: Date = Date.now

    init(name: String, content: String) {
        self.id = UUID()
        self.name = name
        self.content = content
        self.createdAt = .now
    }
}

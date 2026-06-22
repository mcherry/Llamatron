import Foundation
import SwiftData

/// A file the user attached to a session for context. Holds the extracted plain text
/// and its chunked form; chunk embeddings are computed lazily the first time the
/// retrieval strategy runs. Cascade-deleted with its session.
@Model
final class Attachment {
    var id: UUID = UUID()
    var fileName: String = ""
    var fullText: String = ""
    /// Cached estimate so the UI can show size without re-counting.
    var tokenEstimate: Int = 0
    var createdAt: Date = Date.now

    var session: ChatSession?

    @Relationship(deleteRule: .cascade, inverse: \DocumentChunk.attachment)
    var chunks: [DocumentChunk] = []

    init(fileName: String, fullText: String) {
        self.id = UUID()
        self.fileName = fileName
        self.fullText = fullText
        self.tokenEstimate = TokenEstimator.estimate(fullText)
        self.createdAt = .now
    }

    var orderedChunks: [DocumentChunk] {
        chunks.sorted { $0.ordinal < $1.ordinal }
    }
}

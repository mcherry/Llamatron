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
    /// Raw image bytes when this attachment is an image (else `nil`). Images are sent
    /// to vision models rather than chunked/embedded as text.
    var imageData: Data?
    /// Cached vision description of the image, produced by the session's vision model
    /// (the "eyes" step). Empty until extracted; reused across turns.
    var imageDescription: String = ""

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

    /// Creates an image attachment from raw bytes (no text chunks).
    init(fileName: String, imageData: Data) {
        self.id = UUID()
        self.fileName = fileName
        self.imageData = imageData
        self.fullText = ""
        self.tokenEstimate = 0
        self.createdAt = .now
    }

    /// Whether this attachment is an image (vision input) rather than a text document.
    var isImage: Bool { imageData != nil }

    /// Base64 encoding of the image, for the Ollama `images` field.
    var imageBase64: String? {
        imageData?.base64EncodedString()
    }

    var orderedChunks: [DocumentChunk] {
        chunks.sorted { $0.ordinal < $1.ordinal }
    }
}

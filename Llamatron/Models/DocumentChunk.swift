import Foundation
import SwiftData

/// One chunk of an attachment's text, plus its embedding once computed. The embedding
/// is stored as packed `Data` (a contiguous block of 32-bit floats) so SwiftData can
/// persist it cheaply; `embedding` is the typed accessor.
@Model
final class DocumentChunk {
    var id: UUID = UUID()
    var ordinal: Int = 0
    var text: String = ""
    /// `[Float]` packed little-endian; `nil` until the chunk has been embedded.
    var embeddingData: Data?

    var attachment: Attachment?

    init(ordinal: Int, text: String) {
        self.id = UUID()
        self.ordinal = ordinal
        self.text = text
    }

    /// Typed view over `embeddingData`.
    var embedding: [Float]? {
        get { embeddingData.map(Self.decode) }
        set { embeddingData = newValue.map(Self.encode) }
    }

    static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func decode(_ data: Data) -> [Float] {
        var vector = [Float](repeating: 0, count: data.count / MemoryLayout<Float>.stride)
        _ = vector.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return vector
    }
}

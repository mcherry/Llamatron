import SwiftUI
import UniformTypeIdentifiers

/// A simple text-backed document for `.fileExporter`, used to save a session as
/// Markdown or JSON.
struct TextExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .json] }

    var text: String
    var contentType: UTType

    init(text: String, contentType: UTType) {
        self.text = text
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(data: data, encoding: .utf8) ?? ""
        contentType = .plainText
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

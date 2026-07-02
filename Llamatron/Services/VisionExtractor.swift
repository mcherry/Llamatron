import Foundation
import LlamaEngine

/// One image to describe: a plain `Sendable` value (base64 + a name), so it can cross
/// actor boundaries without touching a SwiftData `@Model`.
struct VisionImage: Sendable {
    let id: UUID
    let name: String
    let base64: String
}

/// The result of describing one image. `Sendable`, cached back onto the attachment.
struct VisionDescription: Sendable {
    let id: UUID
    let name: String
    let description: String
}

/// Runs the "eyes" step of a multi-model session: sends an image to a vision model and
/// returns its text description, which the primary model then reasons over. A small
/// `Sendable` helper around `OllamaClient.chat` with an image-bearing turn.
struct VisionExtractor: Sendable {
    var client: OllamaClient
    var visionModel: String

    /// Describes `images` one at a time, returning the descriptions in input order.
    /// Failures yield a short error placeholder rather than throwing, so one bad image
    /// doesn't sink the whole send.
    func describe(_ images: [VisionImage], userPrompt: String) async -> [VisionDescription] {
        var results: [VisionDescription] = []
        for image in images {
            let text = await describeOne(image, userPrompt: userPrompt)
            results.append(VisionDescription(id: image.id, name: image.name, description: text))
        }
        return results
    }

    private func describeOne(_ image: VisionImage, userPrompt: String) async -> String {
        let instruction = """
        Describe this image in thorough detail so someone who cannot see it could \
        answer questions about it. Transcribe any visible text exactly, and note \
        layout, objects, people, colors, and anything notable. The user's question is: \
        "\(userPrompt)". Focus your description on what's relevant to it, but don't omit \
        other important details.
        """
        let request = ChatRequest(
            model: visionModel,
            messages: [ChatTurn(role: Role.user.rawValue, content: instruction, images: [image.base64])],
            contextSize: 4096,
            stream: false,
            think: false
        )
        do {
            var out = ""
            for try await chunk in client.chat(request) { out += chunk.contentDelta }
            let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "(the vision model returned no description)" : trimmed
        } catch {
            return "(couldn't describe \(image.name): \(error.localizedDescription))"
        }
    }
}

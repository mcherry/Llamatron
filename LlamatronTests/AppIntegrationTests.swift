import XCTest
import SwiftData
import LlamaEngine
import LlamaEngineStore

/// App-level integration smoke: proves the Llamatron shell wires the LlamaEngine
/// Store correctly — the schema the app registers (`LlamaEngineStore.models`) builds a
/// container, the models round-trip through it with their cascade relationship intact,
/// and the engine's `ConversationController` instantiates in the app context.
///
/// The exhaustive model/engine behavior lives in the package test suites; this is the
/// thin seam that guarantees the app target links and hosts the engine as expected.
final class AppIntegrationTests: XCTestCase {

    @MainActor
    func testEngineSchemaBuildsContainerAndRoundTripsWithCascade() throws {
        // Build the container exactly as LlamatronApp does: from the engine-owned schema.
        let schema = Schema(LlamaEngineStore.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let session = ChatSession(title: "Integration", modelName: "test-model")
        context.insert(session)
        let message = ChatMessage(role: .user, content: "hello")
        message.session = session
        context.insert(message)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<ChatSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.orderedMessages.count, 1)
        XCTAssertEqual(sessions.first?.orderedMessages.first?.content, "hello")

        // Cascade delete: removing the session removes its messages.
        context.delete(session)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatMessage>()).count, 0)
    }

    @MainActor
    func testConversationControllerInstantiates() {
        let controller = ConversationController()
        XCTAssertFalse(controller.isStreaming)
        XCTAssertNil(controller.errorMessage)
    }
}

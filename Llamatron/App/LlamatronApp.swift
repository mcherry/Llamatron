import SwiftUI
import SwiftData

@main
struct LlamatronApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: ChatSession.self, ChatMessage.self,
                                           Attachment.self, DocumentChunk.self,
                                           PromptPreset.self)
        } catch {
            fatalError("Failed to create the SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)

        Settings {
            SettingsView()
        }
    }
}

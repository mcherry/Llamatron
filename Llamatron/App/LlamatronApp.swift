import SwiftUI
import SwiftData
import LlamaEngine   // Package wired in (Phase 0); real usage begins in Phase 1.

@main
struct LlamatronApp: App {
    let container: ModelContainer

    init() {
        // Make hover tooltips (the field info icons, etc.) appear quickly
        // instead of after AppKit's long default delay. Value is in milliseconds.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])

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

import SwiftUI
import LlamaEngineStore
import SwiftData
import LlamaEngine

@main
struct LlamatronApp: App {
    let container: ModelContainer

    init() {
        // Make hover tooltips (the field info icons, etc.) appear quickly
        // instead of after AppKit's long default delay. Value is in milliseconds.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])

        do {
            // The persistence schema is owned by the engine's Store product.
            #if DEBUG
            if ScreenshotSeed.isActive {
                container = ScreenshotSeed.makeContainer()
            } else {
                container = try ModelContainer(for: Schema(LlamaEngineStore.models))
            }
            #else
            container = try ModelContainer(for: Schema(LlamaEngineStore.models))
            #endif
        } catch {
            fatalError("Failed to create the SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

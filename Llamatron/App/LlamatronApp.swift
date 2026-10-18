import SwiftUI
import LlamaEngineStore
import SwiftData
import CoreData
import LlamaEngine

@main
struct LlamatronApp: App {
    let container: ModelContainer

    init() {
        #if os(macOS)
        Self.migratePreferencesOutOfSandboxContainerIfNeeded()
        #endif

        // Make hover tooltips (the field info icons, etc.) appear quickly
        // instead of after AppKit's long default delay. Value is in milliseconds.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])

        do {
            // The persistence schema is owned by the engine's Store product.
            #if DEBUG
            if ScreenshotSeed.isActive {
                container = ScreenshotSeed.makeContainer()
            } else {
                container = try Self.makeContainer()
            }
            #else
            container = try Self.makeContainer()
            #endif
        } catch {
            fatalError("Failed to create the SwiftData container: \(error)")
        }
    }

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(LlamaEngineStore.models)
        #if os(macOS)
        try adoptLegacyStore(into: storeURL, from: [URL.applicationSupportDirectory.appending(path: "default.store")])
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL)])
        #else
        // iOS keeps the default: inside the app's own sandbox container it can't collide.
        return try ModelContainer(for: schema)
        #endif
    }

    #if os(macOS)
    /// One-time rescue of settings from the pre-unsandboxing container.
    ///
    /// `@AppStorage` writes to `UserDefaults`, which the sandbox redirected into the
    /// container just like Application Support — so unsandboxing silently loses every
    /// setting, search API keys included. Only fills keys that are currently unset, so
    /// re-running it can never overwrite something already re-entered by hand.
    private static func migratePreferencesOutOfSandboxContainerIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: SettingsKey.didMigrateContainerPreferences) else { return }

        let plist = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers/com.llamatron.Llamatron/Data/Library/Preferences")
            .appendingPathComponent("com.llamatron.Llamatron.plist")
        guard let old = NSDictionary(contentsOf: plist) as? [String: Any] else { return }

        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: SettingsKey.didMigrateContainerPreferences)
    }

    // MARK: - Store location

    /// Llamatron's own database. SwiftData's default, `Application Support/default.store`, is
    /// shared by every unsandboxed SwiftData app, so opening it can convert another app's data.
    static let storeURL = URL.applicationSupportDirectory.appending(path: "Llamatron/Llamatron.store")

    /// One-time copy of the first earlier store that holds Llamatron's models into
    /// `destination`. Sources are copied, never opened, so not even a WAL checkpoint touches
    /// them; another app's store is recognised from its copy and discarded.
    static func adoptLegacyStore(into destination: URL, from candidates: [URL]) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { return }
        let folder = destination.deletingLastPathComponent()
        for source in candidates where fm.fileExists(atPath: source.path) {
            let staging = folder.deletingLastPathComponent()
                .appending(path: ".\(folder.lastPathComponent)-staging-\(UUID().uuidString)")
            let staged = staging.appending(path: destination.lastPathComponent)
            // Any failure throws rather than trying the next candidate: history that can't be
            // read should stop the launch, not be replaced by an empty library.
            do {
                try copyStore(from: source, to: staged)
                let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: staged)
                guard (metadata[NSStoreModelVersionHashesKey] as? [String: Any])?["ChatSession"] != nil else {
                    try fm.removeItem(at: staging)
                    continue
                }
                try install(staging, into: folder, storeName: destination.lastPathComponent)
            } catch {
                try? fm.removeItem(at: staging)
                throw error
            }
            return
        }
    }

    /// Copies the database with its WAL, shared-memory file, and external-data folder, which
    /// Core Data names after the store file.
    private static func copyStore(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let oldName = source.deletingPathExtension().lastPathComponent
        let newName = destination.deletingPathExtension().lastPathComponent
        let items = [
            (source.lastPathComponent, destination.lastPathComponent),
            (source.lastPathComponent + "-wal", destination.lastPathComponent + "-wal"),
            (source.lastPathComponent + "-shm", destination.lastPathComponent + "-shm"),
            (".\(oldName)_SUPPORT", ".\(newName)_SUPPORT")
        ]
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        for (from, to) in items {
            let origin = source.deletingLastPathComponent().appending(path: from)
            guard fm.fileExists(atPath: origin.path) else { continue }
            try fm.copyItem(at: origin, to: destination.deletingLastPathComponent().appending(path: to))
        }
    }

    /// Moves a staged store into `folder`, the store file last, so an interruption never
    /// leaves a store there to open without its WAL.
    private static func install(_ staging: URL, into folder: URL, storeName: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else {
            try fm.moveItem(at: staging, to: folder)
            return
        }
        let names = try fm.contentsOfDirectory(atPath: staging.path)
        for name in names.filter({ $0 != storeName }) + [storeName] where names.contains(name) {
            try fm.moveItem(at: staging.appending(path: name), to: folder.appending(path: name))
        }
        try fm.removeItem(at: staging)
    }
    #endif

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

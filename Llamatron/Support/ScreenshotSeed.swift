#if DEBUG
import Foundation
import SwiftData
import LlamaEngine
import LlamaEngineStore

/// Seeds the app with canned, **anonymized** content for automated screenshots.
///
/// Active only when the app is launched with `--uitest-seed` (passed by the screenshot
/// UI test) and compiled only in `DEBUG`, so neither this code nor the fixtures ship in a
/// release. It runs against an **in-memory** store, so it can never read or modify real
/// data. No personal data, real servers, or real URLs appear here.
enum ScreenshotSeed {
    /// Whether the current launch requested screenshot seeding.
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-seed")
    }

    /// An in-memory container so seeding never touches the on-disk store.
    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(
                for: Schema(LlamaEngineStore.models),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("Failed to create the in-memory screenshot container: \(error)")
        }
    }

    /// A generic, public model name — nothing identifying.
    private static let model = "qwen2.5-coder-14b"

    /// Inserts the fixtures and returns the id of the hero session to auto-select.
    @MainActor
    static func populate(_ context: ModelContext) -> ChatSession.ID {
        // Secondary sessions fill the sidebar; each older than the hero so the hero
        // sorts to the top (ContentView orders by `updatedAt` descending).
        let others = [
            "Explain B-trees",
            "Regex for email validation",
            "Summarize the CAP theorem",
            "Refactor this Swift enum",
        ]
        for (index, title) in others.enumerated() {
            let session = ChatSession(title: title, modelName: model, contextSize: 32_768)
            session.backend = .llamaServer
            session.titleIsAuto = false
            session.updatedAt = Date().addingTimeInterval(-Double((index + 1) * 900))
            context.insert(session)
        }

        // Hero session: newest, auto-selected, with a nicely formatted exchange.
        let hero = ChatSession(title: "Swift concurrency", modelName: model, contextSize: 32_768)
        hero.backend = .llamaServer
        hero.titleIsAuto = false
        hero.updatedAt = Date()
        context.insert(hero)

        let prompt = ChatMessage(
            role: .user,
            content: "What's the difference between `async let` and a task group in Swift concurrency?",
            createdAt: Date().addingTimeInterval(-30)
        )
        prompt.session = hero
        context.insert(prompt)

        let reply = ChatMessage(
            role: .assistant,
            content: heroReply,
            createdAt: Date().addingTimeInterval(-25)
        )
        reply.session = hero
        context.insert(reply)

        return hero.id
    }

    /// Markdown answer chosen to show off rendering + syntax highlighting (no Mermaid,
    /// which renders asynchronously in a web view and would race the screenshot).
    private static let heroReply = """
    `async let` and `TaskGroup` both run child tasks concurrently, but they suit different \
    shapes of work.

    **`async let`** is for a *fixed, known* set of tasks. Bind each one, then `await` the \
    results where you need them:

    ```swift
    async let user = fetchUser(id)
    async let posts = fetchPosts(id)
    let profile = try await Profile(user: user, posts: posts)
    ```

    **`TaskGroup`** is for a *dynamic* number of tasks — when the count is decided at runtime:

    ```swift
    let scores = try await withThrowingTaskGroup(of: Int.self) { group in
        for id in ids {
            group.addTask { try await score(for: id) }
        }
        return try await group.reduce(into: []) { $0.append($1) }
    }
    ```

    Rule of thumb: reach for **`async let`** when you can name the tasks up front, and a \
    **task group** when you're iterating over a collection.
    """
}
#endif

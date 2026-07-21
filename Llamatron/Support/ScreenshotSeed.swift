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
            session.updatedAt = Date().addingTimeInterval(-Double((index + 2) * 900))
            context.insert(session)
        }

        // Web-research session: a fetched Wikipedia article attached as a source, with a
        // transcript that reflects the topic being researched. Selected for shot 2.
        let research = ChatSession(title: "Bioluminescence", modelName: "qwen2.5-14b", contextSize: 32_768)
        research.backend = .llamaServer
        research.titleIsAuto = false
        research.updatedAt = Date().addingTimeInterval(-300)
        context.insert(research)

        let source = Attachment(fileName: "Bioluminescence (Wikipedia)", fullText: articleText)
        source.session = research
        context.insert(source)

        let researchQ = ChatMessage(
            role: .user,
            content: "How does bioluminescence work, and which animals use it?",
            createdAt: Date().addingTimeInterval(-320)
        )
        researchQ.session = research
        context.insert(researchQ)

        let researchA = ChatMessage(role: .assistant, content: researchReply,
                                    createdAt: Date().addingTimeInterval(-315))
        researchA.session = research
        setStats(researchA, prompt: 924, eval: 176, nanos: 4_300_000_000, ttft: 0.6, seconds: 4.9)
        context.insert(researchA)

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
        setStats(reply, prompt: 336, eval: 210, nanos: 5_000_000_000, ttft: 0.35, seconds: 5.2)
        context.insert(reply)

        return hero.id
    }

    /// Fills in the timing/token stats that drive the status bar and per-turn caption.
    @MainActor
    private static func setStats(_ message: ChatMessage, prompt: Int, eval: Int,
                                 nanos: Int, ttft: Double, seconds: Double) {
        message.promptTokens = prompt
        message.evalTokens = eval
        message.evalDurationNanos = nanos
        message.firstTokenSeconds = ttft
        message.generationSeconds = seconds
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

    /// A public-knowledge, Wikipedia-style excerpt used as a seeded web-research source
    /// (fetched-page attachment). Nothing personal or identifying.
    private static let articleText = """
    Bioluminescence is the production and emission of light by a living organism. It is a \
    form of chemiluminescence, occurring widely in marine vertebrates and invertebrates, \
    as well as in some fungi, microorganisms, and terrestrial invertebrates such as \
    fireflies.

    In most cases the light is produced by the reaction of a light-emitting molecule, \
    luciferin, with the enzyme luciferase, in the presence of oxygen. Some organisms \
    instead use a pre-charged protein complex, a photoprotein, that emits light when it \
    binds a specific ion such as calcium.

    Bioluminescence serves many functions: attracting mates, luring or detecting prey, \
    camouflage through counter-illumination, and warning or distracting predators. In the \
    deep ocean, where sunlight does not reach, it is the primary source of light, and the \
    majority of animals living there are able to produce it.
    """

    /// The researched answer (Markdown), drawing on the attached article.
    private static let researchReply = """
    Bioluminescence is light made by a living organism — a "cold light" produced \
    chemically rather than by heat.

    **How it works:** most organisms combine a light-emitting molecule called **luciferin** \
    with the enzyme **luciferase** in the presence of oxygen; the reaction releases energy \
    as visible light. Some instead use a pre-charged **photoprotein** that glows when it \
    binds an ion such as calcium.

    **Who uses it** — it's overwhelmingly a marine phenomenon:
    - deep-sea fish, squid, and jellyfish (below the sunlit zone it's the *main* light source)
    - **fireflies** and some beetles on land
    - certain **fungi**, bacteria, and dinoflagellates (the glow you sometimes see in ocean waves)

    Common purposes are attracting mates, luring prey, camouflage by *counter-illumination*, \
    and startling predators.
    """
}
#endif

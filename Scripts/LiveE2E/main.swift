import Foundation

// Standalone live end-to-end driver for the Llamatron context pipeline. It compiles
// the Foundation-only production sources (OllamaClient, ContextAssembler, TextChunker,
// ContextPlanner, …) together with this file and runs them against a real Ollama
// server — outside the app sandbox, so it can reach a LAN server that the hosted
// XCTest process cannot.
//
// Build & run (see Scripts/LiveE2E/run.sh):
//   swiftc -O <production .swift files> Scripts/LiveE2E/main.swift -o /tmp/llamatron-e2e
//   /tmp/llamatron-e2e

func envOr(_ key: String, _ fallback: String) -> String {
    let v = ProcessInfo.processInfo.environment[key]
    return (v?.isEmpty == false) ? v! : fallback
}

let server = envOr("LLAMATRON_SERVER", "http://localhost:11434")
let chatModel = envOr("LLAMATRON_CHAT_MODEL", "qwen-14b")
let embeddingModel = envOr("LLAMATRON_EMBED_MODEL", "nomic-embed-text")
let notesPath = envOr("LLAMATRON_NOTES",
                      FileManager.default.currentDirectoryPath + "/Scripts/LiveE2E/notes.md")

func line() { print(String(repeating: "─", count: 64)) }
var failures = 0
func check(_ name: String, _ condition: Bool) {
    print(condition ? "  ✅ \(name)" : "  ❌ \(name)")
    if !condition { failures += 1 }
}

guard let client = OllamaClient(baseURLString: server, timeout: 180) else {
    print("Invalid server URL: \(server)"); exit(2)
}

func answer(context: String, question: String) async throws -> String {
    let system = """
    Answer the question using only the reference material. If the answer is not \
    present, say you don't know.

    <reference_material>
    \(context)
    </reference_material>
    """
    let request = ChatRequest(
        model: chatModel,
        messages: [ChatTurn(role: Role.system.rawValue, content: system),
                   ChatTurn(role: Role.user.rawValue, content: question)],
        contextSize: 8192, stream: false, numPredict: 64, think: false
    )
    var out = ""
    for try await chunk in client.chat(request) { out += chunk.contentDelta }
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
}

do {
    line()
    print("Llamatron live end-to-end · server \(server)")
    print("chat=\(chatModel)  embed=\(embeddingModel)")
    line()

    // 1) Connectivity.
    let version = try await client.version()
    print("Ollama version: \(version)")
    check("server reachable", !version.isEmpty)

    // 2) Real chunking of a real file.
    let text = try String(contentsOfFile: notesPath, encoding: .utf8)
    let pieces = TextChunker(targetTokens: 60, overlapTokens: 0).chunk(text)
    print("\nChunked \(notesPath.split(separator: "/").last.map(String.init) ?? notesPath) into \(pieces.count) chunks")
    check("produced several chunks", pieces.count > 3)
    let chunks = pieces.enumerated().map { i, t in
        RetrievableChunk(id: UUID(), sourceName: "notes.md", ordinal: i, text: t, embedding: nil)
    }
    let contentTokens = chunks.reduce(0) { $0 + TokenEstimator.estimate($1.text) }
    print("Estimated content size: \(contentTokens) tokens")

    let assembler = ContextAssembler(client: client, chatModel: chatModel, embeddingModel: embeddingModel)

    // 3) Auto planner: too big for a tight budget → retrieval first.
    line(); print("AUTO PLAN (tight budget)")
    let plan = ContextPlanner.plan(contentTokens: contentTokens, available: 80,
                                   mode: .auto, wholeDocTask: false)
    print("Plan: \(plan.map(\.rawValue).joined(separator: " → "))")
    check("auto picks retrieval first", plan.first == .retrieval)

    // 4) Retrieval: focused question about an unguessable fact.
    line(); print("RETRIEVAL  ·  \"codename for the caching layer?\"")
    if let r = await assembler.assemble(chunks: chunks,
                                        query: "What is the codename for the caching layer?",
                                        available: 120, plan: [.retrieval, .truncate]) {
        print("Strategy: \(r.strategyUsed.rawValue)   \(r.note ?? "")")
        print("Context:\n\(r.contextText)")
        check("used retrieval", r.strategyUsed == .retrieval)
        check("retrieved the relevant fact (Pelican)",
              r.contextText.localizedCaseInsensitiveContains("Pelican"))

        // 5) Full loop: model answers from the retrieved context.
        let a = try await answer(context: r.contextText,
                                 question: "What is the codename for the caching layer? Reply with only the name.")
        print("Model answer: \(a)")
        check("model answered from context (Pelican)", a.localizedCaseInsensitiveContains("Pelican"))
    } else {
        check("retrieval returned a result", false)
    }

    // 6) Retrieval for a different fact (port).
    line(); print("RETRIEVAL  ·  \"what port does the server use?\"")
    if let r = await assembler.assemble(chunks: chunks,
                                        query: "What port does the server use?",
                                        available: 100, plan: [.retrieval, .truncate]) {
        print("Context:\n\(r.contextText)")
        check("retrieved the port fact (11434)", r.contextText.contains("11434"))
    } else {
        check("retrieval returned a result", false)
    }

    // 7) Summarize whole document (map-reduce over the real model).
    line(); print("SUMMARIZE  ·  whole-document")
    if let r = await assembler.assemble(chunks: chunks,
                                        query: "Give an overview of this document.",
                                        available: 400, plan: [.summarize, .truncate]) {
        print("Strategy: \(r.strategyUsed.rawValue)")
        print("Summary:\n\(r.contextText)")
        check("used summarize", r.strategyUsed == .summarize)
        check("summary is non-empty",
              !r.contextText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    } else {
        check("summarize returned a result", false)
    }

    line()
    print(failures == 0 ? "ALL CHECKS PASSED ✅" : "\(failures) CHECK(S) FAILED ❌")
    line()
    exit(failures == 0 ? 0 : 1)
} catch {
    print("\nERROR: \(error)")
    exit(3)
}

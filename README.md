# Llamatron

A native macOS chat client and lightweight AI testbed for local large language models.
Llamatron talks to a remote or local [Ollama](https://ollama.com) server and, on
Apple-silicon Macs running macOS 26+, to Apple's on-device Foundation Models — so you
can run, compare, and inspect models from one SwiftUI app.

> Built with SwiftUI, SwiftData, and Swift 6 strict concurrency. macOS 15+ deployment
> target, built against the macOS 26 SDK.

## Features

**Chat**
- Multiple saved sessions in a sidebar; auto-saved and restored via SwiftData.
- Real-time streaming responses with autoscroll, left/right-aligned bubbles, and
  per-turn timestamps and generation time.
- Markdown rendering with syntax-highlighted code blocks (Swift, Python, JS/TS, Go,
  Rust, C/C++, Java, Ruby, SQL, shell, and more), tables, and ` ```mermaid ` diagrams
  rendered locally in a sandboxed web view; fully selectable text and per-turn copy.
- Auto-generated session titles (each session names itself using its own model).
- A resizable composer with an embedded send/stop button — **Return** sends,
  **Shift+Return** inserts a newline.

**Per-session configuration**
- Choose the backend (Ollama or Apple Intelligence) and, for Ollama, the model and
  context window.
- A system prompt with a reusable **prompt library** (saved presets) and a live token /
  context-cost estimate.
- Generation parameters with a fixed **seed** for reproducible output
  (temperature, top-p, top-k, repeat penalty, stop sequences for Ollama; temperature,
  sampling mode, max response tokens, and seed for Apple).
- A reasoning control (Auto / On / Off) for thinking models.
- A **conversation-history strategy** for long chats — send in full, truncate, roll up
  into a running summary, or retrieve the most relevant earlier turns — so sessions keep
  working as they outgrow the context window.

**Vision & multimodal**
- Attach images and ask about them. A vision-capable primary model sees them directly,
  or you can pair a separate **vision model** that describes images for a text-only
  model to reason over.

**Document context (lightweight RAG)**
- Attach text files (file picker or drag-and-drop). Llamatron fits them into the prompt
  with an adaptive strategy chosen by token budget — send in full, retrieve the most
  relevant excerpts (embeddings), summarize, or truncate — and gracefully falls back if
  a step is unavailable.

**AI-testbed tools**
- A collapsible **reasoning/thinking** view for models that expose their chain of
  thought.
- A per-turn **inspector**: latency including time-to-first-token, token counts, the
  retrieved context chunks with similarity scores, conversation-history and vision notes,
  and the exact request payload sent.
- **Session export** to Markdown or JSON.
- A **model manager**: list installed models, pull new ones with a progress bar, delete
  models, and see which are currently loaded.

## Requirements

- macOS 15 (Sequoia) or later. Apple Intelligence support requires a compatible Mac on
  macOS 26+ with Apple Intelligence enabled.
- [Xcode](https://developer.apple.com/xcode/) 26 or later.
- XcodeGen (`brew install xcodegen`).
- An [Ollama](https://ollama.com) server reachable from your Mac (defaults to
  `http://localhost:11434`).

## Getting started

```bash
# generate the Xcode project from project.yml (the .xcodeproj is git-ignored)
xcodegen generate

# open in Xcode
open Llamatron.xcodeproj
```

On first launch, Llamatron opens Settings so you can point it at your Ollama server and
run a connection test before you start a session. You can change the server, defaults,
and embedding model any time from **Settings** (⌘,).

### Command line

```bash
# build
xcodegen generate && xcodebuild -project Llamatron.xcodeproj -scheme Llamatron \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build

# run the unit tests
xcodebuild -project Llamatron.xcodeproj -scheme Llamatron \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

## Project structure

```
Llamatron/
  App/         app entry, ModelContainer, settings keys
  Models/      SwiftData @Model types and value types
  Services/    Ollama client, Apple backend, context assembly, exporters
  ViewModels/  ChatViewModel (send / stream / persist)
  Views/       SwiftUI views
  Support/     pure helpers (tokens, chunking, vectors, planner, markdown)
LlamatronTests/  unit tests (run hermetically, no network)
Scripts/LiveE2E/ optional standalone live end-to-end driver
project.yml      XcodeGen project definition
PLAN.md          original design/build plan
```

## Architecture notes

- The chat UI talks to a small `ChatStreaming` protocol, so both `OllamaClient` and the
  Apple `FoundationModelsBackend` plug into the same view-model and views.
- Swift 6 strict concurrency: SwiftData `@Model` objects stay on the `@MainActor`; only
  `Sendable` value types cross actor boundaries to the networking layer.
- Apple Foundation Models APIs are guarded with `#if canImport(FoundationModels)` and
  `if #available(macOS 26, *)`, so the app builds and runs on the macOS 15 target.
- The unit-test suite is hermetic (no server required). An optional standalone driver in
  `Scripts/LiveE2E/` exercises the real networking code against a live server when you
  want an end-to-end check.

## Testing

```bash
xcodebuild -project Llamatron.xcodeproj -scheme Llamatron \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

The pure logic — JSONL stream parsing, token budgeting, the context-strategy planner,
chunking, vector similarity, conversation-history management, title cleanup, request
encoding, session export, Markdown/table parsing, Mermaid label repair, and syntax
highlighting — is covered by a hermetic unit-test suite (160+ tests, no network).

## License

Llamatron is released under the [MIT License](LICENSE). © 2026 Mike Cherry.

It bundles [Mermaid](https://github.com/mermaid-js/mermaid) (MIT) for diagram rendering;
see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for details.

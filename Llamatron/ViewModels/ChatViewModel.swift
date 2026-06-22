import Foundation
import SwiftData

/// Owns the send/stream/persist flow for one chat session. `@MainActor` so it only
/// ever touches SwiftData `@Model` objects on the main actor; the networking layer
/// hands back plain `Sendable` `ChatChunk` values across the boundary.
@MainActor
@Observable
final class ChatViewModel {
    var isStreaming = false
    var errorMessage: String?
    /// Set after context assembly so the UI can show which strategy was used.
    var contextInfo: ContextInfo?

    private var streamTask: Task<Void, Never>?

    /// Inserts the user turn, opens an empty assistant turn, assembles any attached
    /// document context, then streams deltas into the assistant turn. Assembly and
    /// streaming both run in the same cancellable task.
    func send(text: String,
              session: ChatSession,
              client: OllamaClient?,
              embeddingModel: String,
              modelContext: ModelContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, session.isConfigured else { return }

        // Resolve the chat backend up front. Ollama needs a reachable server; Apple
        // Intelligence runs entirely on-device and needs no client.
        let backend: ChatStreaming
        switch session.backend {
        case .ollama:
            guard let client else {
                errorMessage = "Invalid server URL. Check Settings."
                return
            }
            backend = client
        case .appleIntelligence:
            backend = FoundationModelsBackend(options: session.appleOptions)
        }

        errorMessage = nil
        contextInfo = nil

        let userMessage = ChatMessage(role: .user, content: trimmed)
        userMessage.session = session
        modelContext.insert(userMessage)

        let assistant = ChatMessage(role: .assistant, content: "")
        assistant.session = session
        modelContext.insert(assistant)

        session.updatedAt = .now

        isStreaming = true
        streamTask = Task { [weak self] in
            guard let self else { return }

            // Assemble document context (may embed/summarize) before the request.
            let contextBlock = await self.assembleContext(query: trimmed,
                                                          session: session,
                                                          into: assistant,
                                                          client: client,
                                                          embeddingModel: embeddingModel)

            if Task.isCancelled {
                if assistant.content.isEmpty { modelContext.delete(assistant) }
                self.isStreaming = false
                return
            }

            let turns = self.buildTurns(for: session, contextBlock: contextBlock)
            let request = ChatRequest(model: session.modelName,
                                      messages: turns,
                                      contextSize: session.contextSize,
                                      think: session.reasoningMode.think,
                                      parameters: session.generationParameters)
            assistant.requestPayload = RequestInspector.payload(for: request,
                                                                backend: session.backend,
                                                                appleOptions: session.appleOptions)
            await self.consume(backend.chat(request),
                               into: assistant,
                               session: session,
                               titleBackend: backend,
                               modelContext: modelContext)
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Streaming

    private func consume(_ stream: AsyncThrowingStream<ChatChunk, Error>,
                         into assistant: ChatMessage,
                         session: ChatSession,
                         titleBackend: ChatStreaming,
                         modelContext: ModelContext) async {
        let started = Date()
        var sawFirstToken = false
        do {
            for try await chunk in stream {
                if !sawFirstToken,
                   !chunk.contentDelta.isEmpty || !chunk.thinkingDelta.isEmpty {
                    assistant.firstTokenSeconds = Date().timeIntervalSince(started)
                    sawFirstToken = true
                }
                if chunk.isReplacement {
                    // Cumulative snapshot (Apple backend): replace the body.
                    assistant.content = chunk.contentDelta
                } else {
                    if !chunk.contentDelta.isEmpty {
                        assistant.content += chunk.contentDelta
                    }
                    if !chunk.thinkingDelta.isEmpty {
                        assistant.thinking += chunk.thinkingDelta
                    }
                }
                if chunk.done {
                    assistant.promptTokens = chunk.promptTokens
                    assistant.evalTokens = chunk.evalTokens
                    assistant.evalDurationNanos = chunk.evalDurationNanos
                }
            }
            assistant.generationSeconds = Date().timeIntervalSince(started)
            session.updatedAt = .now
            isStreaming = false
            await maybeGenerateTitle(for: session, client: titleBackend)
        } catch {
            isStreaming = false
            let cancelled = (error is CancellationError) || (error as? URLError)?.code == .cancelled
            if cancelled {
                // The user stopped generation; keep whatever streamed so far.
                if !assistant.content.isEmpty {
                    assistant.generationSeconds = Date().timeIntervalSince(started)
                }
                session.updatedAt = .now
                return
            }
            // A real failure with no content: drop the empty assistant bubble.
            if assistant.content.isEmpty {
                modelContext.delete(assistant)
            } else {
                assistant.generationSeconds = Date().timeIntervalSince(started)
            }
            errorMessage = error.localizedDescription
        }
    }

    private func buildTurns(for session: ChatSession, contextBlock: String?) -> [ChatTurn] {
        var turns: [ChatTurn] = []
        let systemPrompt = session.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !systemPrompt.isEmpty {
            turns.append(ChatTurn(role: Role.system.rawValue, content: systemPrompt))
        }
        if let contextBlock, !contextBlock.isEmpty {
            let preamble = """
            You have been given reference material to help answer the conversation. \
            Use it when relevant; if it doesn't contain the answer, say so rather than guessing.

            <reference_material>
            \(contextBlock)
            </reference_material>
            """
            turns.append(ChatTurn(role: Role.system.rawValue, content: preamble))
        }
        // Skip the system role (handled above) and the in-flight empty assistant turn.
        for message in session.orderedMessages where message.role != .system && !message.content.isEmpty {
            turns.append(ChatTurn(role: message.role.rawValue, content: message.content))
        }
        return turns
    }

    // MARK: - Context assembly

    /// Builds the document-context block for this turn, if the session has
    /// attachments. Gathers `Sendable` chunks on the main actor, runs the strategy
    /// ladder off-actor via `ContextAssembler`, then persists any new embeddings.
    private func assembleContext(query: String,
                                 session: ChatSession,
                                 into assistant: ChatMessage,
                                 client: OllamaClient?,
                                 embeddingModel: String) async -> String? {
        let attachments = session.orderedAttachments
        guard !attachments.isEmpty else { return nil }
        // Context assembly (embeddings, summarization) runs on the Ollama server. An
        // Apple-only session with no server simply sends without document context.
        guard let client else { return nil }

        var chunks: [RetrievableChunk] = []
        var ordinal = 0
        for attachment in attachments {
            for chunk in attachment.orderedChunks {
                chunks.append(RetrievableChunk(id: chunk.id,
                                               sourceName: attachment.fileName,
                                               ordinal: ordinal,
                                               text: chunk.text,
                                               embedding: chunk.embedding))
                ordinal += 1
            }
        }
        guard !chunks.isEmpty else { return nil }

        let contentTokens = chunks.reduce(0) { $0 + TokenEstimator.estimate($1.text) }
        let historyTokens = session.orderedMessages
            .filter { $0.role != .system && !$0.content.isEmpty }
            .reduce(0) { $0 + TokenEstimator.estimate($1.content) }
        let budget = ContextBudget(contextSize: session.contextSize,
                                   systemTokens: TokenEstimator.estimate(session.systemPrompt),
                                   historyTokens: historyTokens,
                                   userTokens: TokenEstimator.estimate(query))
        let available = budget.availableForContext
        guard available > 0 else { return nil }

        let plan = ContextPlanner.plan(contentTokens: contentTokens,
                                       available: available,
                                       mode: session.contextMode,
                                       wholeDocTask: ContextPlanner.looksLikeWholeDocTask(query))
        guard !plan.isEmpty else { return nil }

        let assembler = ContextAssembler(client: client,
                                         chatModel: session.modelName,
                                         embeddingModel: embeddingModel)
        guard let result = await assembler.assemble(chunks: chunks,
                                                    query: query,
                                                    available: available,
                                                    plan: plan) else { return nil }

        // Persist freshly computed embeddings back onto the @Model chunks.
        if !result.newEmbeddings.isEmpty {
            let chunksByID = Dictionary(attachments.flatMap(\.chunks).map { ($0.id, $0) },
                                        uniquingKeysWith: { first, _ in first })
            for (id, vector) in result.newEmbeddings {
                chunksByID[id]?.embedding = vector
            }
        }

        contextInfo = ContextInfo(strategy: result.strategyUsed,
                                  sources: result.sourceLabels,
                                  note: result.note)
        if !result.retrieved.isEmpty {
            assistant.retrievalData = try? JSONEncoder().encode(result.retrieved)
        }
        return result.contextText
    }

    // MARK: - Auto-naming

    private func maybeGenerateTitle(for session: ChatSession, client: ChatStreaming) async {
        guard session.titleIsAuto else { return }
        let conversation = session.orderedMessages.filter { $0.role != .system }
        guard let firstUser = conversation.first(where: { $0.role == .user })?.content,
              let firstAssistant = conversation.first(where: { $0.role == .assistant })?.content,
              !firstAssistant.isEmpty else { return }

        let title = await TitleGenerator.generate(model: session.modelName,
                                                   userMessage: firstUser,
                                                   assistantReply: firstAssistant,
                                                   client: client)
        // Re-check: the user may have renamed while the title was generating. Mark the
        // session done auto-naming so it only happens once (until an explicit reset).
        if let title, session.titleIsAuto {
            session.title = title
            session.titleIsAuto = false
        }
    }
}

/// A short summary of how attached context was fitted into the last turn, for display.
struct ContextInfo: Equatable {
    var strategy: ContextStrategy
    var sources: [String]
    var note: String?

    var summary: String {
        let sourceList = sources.isEmpty ? "" : " · " + sources.joined(separator: ", ")
        return "Context: \(strategy.label)\(sourceList)"
    }
}

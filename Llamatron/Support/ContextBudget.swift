import Foundation

/// Computes how many tokens are free for injected document context after reserving
/// room for the system prompt, conversation history, the new user message, and the
/// model's reply. Pure, so it is unit-tested.
struct ContextBudget {
    var contextSize: Int
    var systemTokens: Int
    var historyTokens: Int
    var userTokens: Int

    /// Tokens kept in reserve for the model's reply: a quarter of the window, bounded
    /// so tiny windows still leave something and huge ones don't over-reserve.
    var responseReserve: Int {
        max(512, min(2048, contextSize / 4))
    }

    /// Tokens left for injected document context (never negative).
    var availableForContext: Int {
        let used = systemTokens + historyTokens + userTokens + responseReserve
        return max(0, contextSize - used)
    }
}

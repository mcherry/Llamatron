import Foundation

/// Serializes a chat session to Markdown or JSON for sharing or offline analysis.
/// Pure string builders (no SwiftData types cross in), so they are unit-testable by
/// passing plain values.
enum SessionExporter {
    /// A plain snapshot of one turn for export. Decoupled from the `@Model`.
    struct Turn: Sendable {
        var role: String
        var content: String
        var thinking: String
        var createdAt: Date
        var promptTokens: Int?
        var evalTokens: Int?
        var generationSeconds: Double?
        var firstTokenSeconds: Double?
    }

    struct Session: Sendable {
        var title: String
        var backend: String
        var model: String
        var contextSize: Int
        var systemPrompt: String
        var createdAt: Date
        var turns: [Turn]
    }

    // MARK: - Markdown

    static func markdown(_ session: Session) -> String {
        var out = "# \(session.title)\n\n"
        out += "- **Backend:** \(session.backend)\n"
        if !session.model.isEmpty {
            out += "- **Model:** \(session.model)\n"
        }
        out += "- **Context size:** \(session.contextSize)\n"
        out += "- **Created:** \(iso(session.createdAt))\n"
        let trimmedSystem = session.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSystem.isEmpty {
            out += "\n## System Prompt\n\n\(trimmedSystem)\n"
        }
        out += "\n---\n"

        for turn in session.turns {
            let speaker = turn.role == Role.user.rawValue ? "🧑 You" : "🤖 Assistant"
            out += "\n### \(speaker)\n\n"
            if !turn.thinking.isEmpty {
                out += "<details><summary>Reasoning</summary>\n\n\(turn.thinking)\n\n</details>\n\n"
            }
            out += "\(turn.content)\n"
            if let stats = statsLine(turn) {
                out += "\n_\(stats)_\n"
            }
        }
        return out
    }

    private static func statsLine(_ turn: Turn) -> String? {
        var parts: [String] = []
        if let p = turn.promptTokens { parts.append("\(p) prompt tokens") }
        if let e = turn.evalTokens { parts.append("\(e) response tokens") }
        if let s = turn.generationSeconds, s > 0 { parts.append(String(format: "%.1fs", s)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - JSON

    static func json(_ session: Session) -> String {
        let turns: [[String: Any]] = session.turns.map { turn in
            var dict: [String: Any] = [
                "role": turn.role,
                "content": turn.content,
                "createdAt": iso(turn.createdAt)
            ]
            if !turn.thinking.isEmpty { dict["thinking"] = turn.thinking }
            if let v = turn.promptTokens { dict["promptTokens"] = v }
            if let v = turn.evalTokens { dict["evalTokens"] = v }
            if let v = turn.generationSeconds { dict["generationSeconds"] = v }
            if let v = turn.firstTokenSeconds { dict["firstTokenSeconds"] = v }
            return dict
        }
        let object: [String: Any] = [
            "title": session.title,
            "backend": session.backend,
            "model": session.model,
            "contextSize": session.contextSize,
            "systemPrompt": session.systemPrompt,
            "createdAt": iso(session.createdAt),
            "turns": turns
        ]
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}

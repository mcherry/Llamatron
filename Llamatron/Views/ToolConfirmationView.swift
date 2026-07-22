import SwiftUI
import LlamaEngine

/// Bridges the engine's async confirmation hook to a SwiftUI sheet. The headless agent
/// loop calls `handler`, which suspends until the user taps a button in the presented
/// `ToolConfirmationView`; that choice resumes the loop. This is the human-in-the-loop
/// wall — nothing above the `pure` tier runs without an explicit approval here.
@MainActor
@Observable
final class ToolApprovalCoordinator {
    /// The call awaiting a decision, or nil. Drives sheet presentation.
    var pending: ToolConfirmationRequest?
    private var continuation: CheckedContinuation<ToolConfirmationOutcome, Never>?

    /// The `@Sendable` handler to hand to `ToolContext.confirm`. Hops to the main actor
    /// and awaits the user's decision.
    var handler: ToolConfirmationHandler {
        { [weak self] request in
            guard let self else { return .denied }
            return await self.requestApproval(request)
        }
    }

    private func requestApproval(_ request: ToolConfirmationRequest) async -> ToolConfirmationOutcome {
        // The loop runs calls sequentially, but guard against an overlapping request rather
        // than deadlock on a second continuation.
        if continuation != nil { return .denied }
        return await withCheckedContinuation { cont in
            self.continuation = cont
            self.pending = request
        }
    }

    /// Resolve the pending request with the user's choice (a dismissal resolves `.denied`).
    func respond(_ outcome: ToolConfirmationOutcome) {
        pending = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: outcome)
    }
}

/// The confirmation sheet: the exact tool, its risk tier, and its *literal* arguments, so
/// the user sees precisely what the model is asking to do before anything runs.
struct ToolConfirmationView: View {
    let request: ToolConfirmationRequest
    let onDecision: (ToolConfirmationOutcome) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Run “\(request.toolName)”?").font(.headline)
                    tierBadge
                }
                Spacer()
            }

            if !request.toolDescription.isEmpty {
                Text(request.toolDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Arguments")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(request.argumentsJSON)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 160)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            Text("The model requested this. Nothing runs until you approve. Treat the arguments as coming from the model — they may reflect content it read, so verify them.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Deny", role: .cancel) { onDecision(.denied) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                // "Approve for Chat" is never offered for a `mutating` tool.
                if request.riskTier != .mutating {
                    Button("Approve for Chat") { onDecision(.approvedForSession) }
                }
                Button("Approve Once") { onDecision(.approvedOnce) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        #if os(macOS)
        .frame(width: 440)
        #endif
    }

    private var tierBadge: some View {
        Text(tierLabel)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tierColor.opacity(0.18), in: Capsule())
            .foregroundStyle(tierColor)
    }

    private var tierLabel: String {
        switch request.riskTier {
        case .pure: return "pure"
        case .readLocal: return "reads local data"
        case .network: return "network request"
        case .mutating: return "changes data"
        }
    }

    private var tierColor: Color {
        switch request.riskTier {
        case .pure: return .green
        case .readLocal: return .blue
        case .network: return .orange
        case .mutating: return .red
        }
    }
}

import SwiftUI
import LlamaEngineStore
import LlamaEngine

/// The per-chat tool controls: a master "let the model use tools" switch plus a per-tool
/// allow-list with risk-tier badges. Emits bare rows (no surrounding container) so it can
/// be dropped into the Session Settings form *and* the composer's tools popover, keeping
/// one source of truth for the toggles.
struct ToolsPickerView: View {
    @Bindable var session: ChatSession

    var body: some View {
        Toggle(isOn: $session.toolsEnabled) {
            Label("Let the model use tools", systemImage: "wrench.and.screwdriver")
        }
        if session.toolsEnabled {
            ForEach(ToolRegistry.builtInTools, id: \.name) { tool in
                Toggle(isOn: toolBinding(tool.name)) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(tool.name)
                            ToolTierBadge(tier: tool.riskTier)
                        }
                        Text(tool.description)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Binds a tool's allow-list membership. Turning a tool off also revokes any prior
    /// "approve for chat" so it must be re-confirmed if re-enabled.
    private func toolBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { session.allowedToolNames.contains(name) },
            set: { isOn in
                if isOn {
                    if !session.allowedToolNames.contains(name) {
                        session.allowedToolNames.append(name)
                    }
                } else {
                    session.allowedToolNames.removeAll { $0 == name }
                    session.approvedToolNames.removeAll { $0 == name }
                }
            })
    }
}

/// A small risk-tier chip (pure / local / network / writes) shown next to a tool name.
struct ToolTierBadge: View {
    let tier: ToolRiskTier

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch tier {
        case .pure: return "pure"
        case .readLocal: return "local"
        case .network: return "network"
        case .mutating: return "writes"
        }
    }

    private var color: Color {
        switch tier {
        case .pure: return .green
        case .readLocal: return .blue
        case .network: return .orange
        case .mutating: return .red
        }
    }
}

/// The composer's tools affordance: a wrench button that reflects how many tools are on
/// for this chat and opens a popover to toggle them — putting the per-chat tool gate right
/// where the user types, instead of only inside Session Settings.
struct SessionToolsButton: View {
    @Bindable var session: ChatSession
    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Image(systemName: "wrench")
                .font(.title3)
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            Form {
                Section {
                    ToolsPickerView(session: session)
                } header: {
                    Text("Tools for this chat")
                } footer: {
                    Text("A pure tool (like the clock) runs on its own; anything that reads local data or reaches the network asks you to approve first. Tools run on your device, never on the server.")
                }
            }
            .formStyle(.grouped)
            .frame(width: 340, height: 420)
        }
    }

    /// On when tools are enabled for the chat *and* at least one is allow-listed.
    private var isActive: Bool { session.toolsEnabled && !session.allowedToolNames.isEmpty }

    private var helpText: String {
        guard session.toolsEnabled else { return "Tools — off for this chat" }
        let count = session.allowedToolNames.count
        return count == 0 ? "Tools — none enabled yet" : "Tools — \(count) enabled"
    }
}

import SwiftUI

/// Chat transcript + composer used as the detail column inside ProjectsView.
///
/// Reuses `store.bridge` for the bidirectional connection. The bridge is
/// shared across project switches — when the user clicks "Start new chat"
/// in a different project, the bridge stops and restarts in the new cwd.
struct ChatPane: View {
    @Environment(HarnessStore.self) private var store
    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    private var planSheetBinding: Binding<Bool> {
        Binding(
            get: { store.bridge.pendingPlan != nil },
            set: { if !$0 { store.bridge.dismissPlan() } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            transcript
            Divider()
            composer
        }
        .navigationTitle("Chat")
        .sheet(isPresented: planSheetBinding) {
            if let plan = store.bridge.pendingPlan {
                PlanApprovalSheet(
                    plan: plan,
                    onAccept: {
                        Task { @MainActor in store.bridge.approvePlan() }
                    },
                    onReject: { feedback in
                        Task { @MainActor in store.bridge.rejectPlan(feedback: feedback) }
                    }
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Stop chat", role: .destructive) { Task { await store.bridge.stop() } }
                        .disabled(!store.bridge.isRunning)
                    Button("Clear transcript") { Task { @MainActor in store.bridge.clear() } }
                    Divider()
                    Toggle("Plan Mode", isOn: Binding(
                        get: { store.bridge.isPlanMode },
                        set: { newVal in
                            Task { @MainActor in
                                store.bridge.setPlanMode(newVal)
                                if !store.bridge.isRunning {
                                    store.bridge.start(cwd: nil)
                                }
                            }
                        }
                    ))
                } label: {
                    Label("Session", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            if store.bridge.isRunning {
                if store.bridge.isThinking {
                    ProgressView()
                        .controlSize(.small)
                    Text("thinking…")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                    Text("Live")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                }
                Button {
                    Task { await store.bridge.interrupt() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!store.bridge.isThinking)
            } else if store.bridge.isStarting {
                ProgressView()
                    .controlSize(.small)
                Text("Starting…")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Button {
                    Task { await store.bridge.start(cwd: nil) }
                } label: {
                    Label("Start NCode session", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            Text("cwd: \(store.bridge.cwd.path)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let err = store.bridge.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var transcript: some View {
        if store.bridge.events.isEmpty {
            ContentUnavailableView(
                store.bridge.isRunning ? "Send a message below to start chatting" : "Start an NCode session to chat",
                systemImage: "bubble.left.and.bubble.right",
                description: Text(store.bridge.statusBanner)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(store.bridge.events) { ev in
                            ChatRow(event: ev).id(ev.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onChange(of: store.bridge.events.last?.id) { _, newID in
                    if let id = newID {
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if !store.bridge.statusBanner.isEmpty {
                Text(store.bridge.statusBanner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextEditor(text: $draft)
                    .font(.system(.callout, design: .default))
                    .frame(minHeight: 36, maxHeight: 120)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .focused($inputFocused)
                    .disabled(!store.bridge.isRunning)

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.bridge.isRunning)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.thinMaterial)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, store.bridge.isRunning else { return }
        store.bridge.send(text)
        draft = ""
    }
}

private struct ChatRow: View {
    let event: ChatEvent

    var body: some View {
        VStack(alignment: event.alignment, spacing: 4) {
            switch event {
            case .user(let text, let ts, _):
                userBubble(text: text, ts: ts)
            case .assistant(let blocks, let ts, _):
                assistantMessages(blocks: blocks, ts: ts)
            case .system(let text, let ts, _):
                systemBanner(text: text, ts: ts)
            case .result(let text, let subtype, let durationMs, let numTurns,
                         let isError, let usage, let cost, let stopReason,
                         let ts, _):
                resultFooter(text: text, subtype: subtype, durationMs: durationMs,
                             numTurns: numTurns, isError: isError, usage: usage,
                             cost: cost, stopReason: stopReason, ts: ts)
            case .other(let t, let raw, let ts, _):
                otherRow(type: t, raw: raw, ts: ts)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment(for: event))
    }

    private func frameAlignment(for ev: ChatEvent) -> Alignment {
        switch ev.alignment {
        case .trailing: return .trailing
        default: return .leading
        }
    }

    private func userBubble(text: String, ts: Date) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(text)
                .font(.system(.body))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                .textSelection(.enabled)
            stampLabel(ts)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func assistantMessages(blocks: [AssistantBlock], ts: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
            stampLabel(ts)
        }
        .frame(alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: AssistantBlock) -> some View {
        switch block {
        case .text(let s):
            Text(s)
                .font(.system(.body))
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .toolUse(let name, let id, let inputJSON):
            ToolUseDisclosure(name: name, toolUseId: id, inputJSON: inputJSON)
        case .toolResult(let toolUseId, let content):
            ToolResultCard(toolUseId: toolUseId, content: content)
        }
    }

    private func systemBanner(text: String, ts: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "gearshape")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption.italic())
                .foregroundStyle(.tertiary)
            Text(ts.formatted(date: .omitted, time: .standard))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultFooter(text: String, subtype: String, durationMs: Int,
                              numTurns: Int, isError: Bool, usage: TurnUsage?,
                              cost: Double, stopReason: String, ts: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: isError ? "xmark.octagon.fill" : "flag.checkered")
                    .foregroundStyle(isError ? .red : .green)
                Text(subtype.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(isError ? .red : .green)
                Text(stopReason)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(durationMs)ms")
                    .font(.caption2.bold().monospacedDigit())
                if numTurns > 1 {
                    Text("· \(numTurns) turns")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if !text.isEmpty {
                Text(text)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let u = usage {
                HStack(spacing: 10) {
                    Text("in:\(u.inputTokens)")
                    Text("out:\(u.outputTokens)")
                    if u.cacheRead > 0 { Text("cache:\(u.cacheRead)") }
                    Text(String(format: "$%.4f", cost))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func otherRow(type: String, raw: String, ts: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("[\(type)]")
                .font(.caption2.bold().monospaced())
                .foregroundStyle(.secondary)
            Text(raw.prefix(200))
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .truncationMode(.tail)
            stampLabel(ts)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stampLabel(_ ts: Date) -> some View {
        Text(ts.formatted(date: .omitted, time: .standard))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
    }
}

private struct ToolUseDisclosure: View {
    let name: String
    let toolUseId: String
    let inputJSON: String
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(inputJSON)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(.orange)
                Text(name)
                    .font(.system(.callout, design: .monospaced).bold())
                Spacer()
                Text(toolUseId.prefix(8))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ToolResultCard: View {
    let toolUseId: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(.green)
                Text("result — \(toolUseId.prefix(8))")
                    .font(.caption.bold().monospaced())
            }
            Text(content.prefix(800))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
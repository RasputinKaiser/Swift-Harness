import SwiftUI

struct ChatPane: View {
    @Environment(HarnessStore.self) private var store
    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            transcript
            Divider()
            composer
        }
        .navigationTitle("Chat")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Start chat") { Task { await store.bridge.start(cwd: liveSessionCWD) } }
                    Button("Stop chat", role: .destructive) { Task { await store.bridge.stop() } }
                    Button("Clear transcript") { Task { @MainActor in store.bridge.clear() } }
                } label: {
                    Label("Session", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            if store.bridge.isRunning {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                Text("Live")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
            } else if store.bridge.isStarting {
                ProgressView()
                    .controlSize(.small)
                Text("Starting…")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Button {
                    Task { await store.bridge.start(cwd: liveSessionCWD) }
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
                .keyboardShortcut(.return, modifiers: [.command])
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

    /// If there's a live session being observed in the SessionsPane, use its cwd
    /// as the chat's working directory. Otherwise default to ~.
    private var liveSessionCWD: URL? {
        store.liveSession.attachedSession?.cwdURL
    }
}

private struct ChatRow: View {
    let event: ChatEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: event.iconName)
                .foregroundStyle(event.tint)
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(event.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(label)
                        .font(.caption2.bold())
                        .foregroundStyle(event.tint)
                }
                Text(event.text.isEmpty ? "(empty)" : event.text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
    }

    private var label: String {
        switch event {
        case .user: "user"
        case .assistant: "assistant"
        case .system: "system"
        case .result: "result"
        case .other(let t, _, _, _): t
        }
    }

    private var rowBackground: Color {
        switch event {
        case .user: Color.blue.opacity(0.06)
        case .assistant: Color.purple.opacity(0.04)
        case .system: Color.gray.opacity(0.06)
        case .result: Color.indigo.opacity(0.06)
        case .other: Color.clear
        }
    }
}
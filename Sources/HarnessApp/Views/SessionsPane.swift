import SwiftUI

struct SessionsPane: View {
    @Environment(HarnessStore.self) private var store
    @State private var sessions: [SessionDescriptor] = []
    @State private var selectedSessionPID: Int?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            sessionPicker
            Divider()
            eventList
            Divider()
            footer
        }
        .navigationTitle("Sessions")
        .task {
            sessions = SessionIndex.scan()
            if selectedSessionPID == nil, let live = sessions.first(where: { $0.isAlive }) {
                selectedSessionPID = live.pid
                store.liveSession.attach(to: live)
            } else if let pid = selectedSessionPID,
                      let s = sessions.first(where: { $0.pid == pid }) {
                store.liveSession.attach(to: s)
            }
        }
        .onAppear { refreshSessions() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Live Session Activity")
                    .font(.headline)
                if let s = attachedSession {
                    Text(s.sessionId.prefix(8) + " · " + relativeStart(s))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No session attached")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { refreshSessions() } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Picker

    @ViewBuilder
    private var sessionPicker: some View {
        if sessions.isEmpty {
            ContentUnavailableView(
                "No sessions found",
                systemImage: "tray",
                description: Text("~/.ncode/sessions/*.json returned no entries")
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 30)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sessions) { desc in
                        sessionChip(desc)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private func sessionChip(_ s: SessionDescriptor) -> some View {
        let isSelected = selectedSessionPID == s.pid
        return Button {
            selectedSessionPID = s.pid
            store.liveSession.attach(to: s)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(s.isAlive ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                Text(s.isAlive ? "live" : "closed")
                    .font(.caption2.bold())
                    .foregroundStyle(s.isAlive ? .green : .secondary)
                Text(sessionLabel(s))
                    .font(.system(.caption, design: .monospaced))
                if let name = s.name {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
                       in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Event list

    @ViewBuilder
    private var eventList: some View {
        if store.liveSession.events.isEmpty {
            ContentUnavailableView(
                "No activity yet",
                systemImage: "waveform.path",
                description: Text("Waiting for tool calls / messages…")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(store.liveSession.displayEvents) { event in
                            ActivityRow(event: event)
                                .id(event.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onChange(of: store.liveSession.events.last?.id) { _, newId in
                    if let id = newId {
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet")
                .foregroundStyle(.secondary)
            Text("\(store.liveSession.events.count) shown")
                .font(.caption.monospacedDigit())
            Text("·")
                .foregroundStyle(.secondary)
            Text("\(store.liveSession.totalEventsObserved) total")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            statusLabel
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch store.liveSession.status {
        case .idle:
            Label("Idle", systemImage: "moon").foregroundStyle(.secondary)
        case .attaching(let u):
            Label("Attaching…", systemImage: "arrow.triangle.pull").foregroundStyle(.orange)
            Text(u.lastPathComponent).font(.caption2).foregroundStyle(.tertiary)
        case .tailing(let u):
            Label("Tailing", systemImage: "antenna.radiowaves.left.and.right").foregroundStyle(.green)
            Text(u.lastPathComponent).font(.caption2).foregroundStyle(.tertiary)
        case .failed(let why):
            Label(why, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                .lineLimit(1)
                .truncationMode(.tail)
        case .finished(let u):
            Label("Closed", systemImage: "stop.fill").foregroundStyle(.secondary)
            Text(u.lastPathComponent).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private var attachedSession: SessionDescriptor? {
        store.liveSession.attachedSession
    }

    private func sessionLabel(_ s: SessionDescriptor) -> String {
        var parts: [String] = []
        parts.append("pid:\(s.pid)")
        if s.isInteractive { parts.append("interactive") }
        return parts.joined(separator: " ")
    }

    private func relativeStart(_ s: SessionDescriptor) -> String {
        s.startedAt.formatted(.relative(presentation: .named))
    }

    private func refreshSessions() {
        sessions = SessionIndex.scan()
    }
}

private struct ActivityRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: event.iconName)
                .foregroundStyle(tint)
                .frame(width: 16, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(event.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(label)
                        .font(.caption2.bold())
                        .foregroundStyle(tint)
                }
                Text(event.shortText)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(eventBackground, in: RoundedRectangle(cornerRadius: 4))
    }

    private var tint: Color {
        switch event.tint {
        case .user: .blue
        case .assistant: .purple
        case .system: .gray
        case .misc: .secondary
        }
    }

    private var label: String {
        switch event {
        case .user: "user"
        case .assistant: "assistant"
        case .system: "system"
        case .other(let t, _, _): t
        }
    }

    private var eventBackground: Color {
        switch event {
        case .user: Color.blue.opacity(0.05)
        case .assistant: Color.purple.opacity(0.05)
        case .system: Color.gray.opacity(0.05)
        case .other: Color.clear
        }
    }
}
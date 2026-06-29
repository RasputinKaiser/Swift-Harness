import SwiftUI

/// Shows the historical transcript of a selected (historical OR live) session.
/// Reuses `SessionActivityStore` with `loadHistory: true`.
///
/// Used as the right column in ProjectsView when the user picks a session
/// (vs. starting a new chat, which uses ChatPane).
struct SessionTranscriptView: View {
    @Environment(HarnessStore.self) private var store
    let session: SessionDescriptor

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            eventList
            Divider()
            footer
        }
        .navigationTitle("Session Transcript")
        .task {
            if store.liveSession.attachedSession?.sessionId != session.sessionId {
                store.liveSession.attach(to: session, loadHistory: true)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcript")
                    .font(.headline)
                Text(session.sessionId)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if session.startedAtMs > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let name = session.name {
                        Text(name)
                            .font(.caption2.bold())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var eventList: some View {
        if store.liveSession.events.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(store.liveSession.displayEvents) { event in
                            TranscriptRow(event: event)
                                .id(event.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .onChange(of: store.liveSession.events.last?.id) { _, newID in
                    if let id = newID {
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch store.liveSession.status {
        case .failed(let why):
            ContentUnavailableView(
                "Failed to load transcript",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(why).foregroundStyle(.red)
            )
        case .attaching, .idle:
            ContentUnavailableView(
                "Loading transcript…",
                systemImage: "hourglass"
            )
        default:
            ContentUnavailableView(
                "No events yet",
                systemImage: "doc.text",
                description: Text("Session has no recorded user/assistant activity.")
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet")
                .foregroundStyle(.secondary)
            Text("\(store.liveSession.events.count) shown")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("·")
                .foregroundStyle(.secondary)
            Text("\(store.liveSession.totalEventsObserved) total")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
            switch store.liveSession.status {
            case .tailing(let url):
                Label("Tailing \(url.lastPathComponent)", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(.green)
            case .attaching:
                Label("Attaching…", systemImage: "arrow.triangle.pull")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            case .failed(let why):
                Label(why, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.head)
            case .idle:
                Label("Idle", systemImage: "moon")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .finished:
                Label("Finished", systemImage: "stop.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }
}

private struct TranscriptRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: event.iconName)
                .foregroundStyle(tint)
                .frame(width: 14, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(event.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(label)
                        .font(.caption2.bold())
                        .foregroundStyle(tint)
                }
                Text(event.shortText.isEmpty ? "(no text)" : event.shortText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 4))
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

    private var rowBackground: Color {
        switch event {
        case .user: Color.blue.opacity(0.04)
        case .assistant: Color.purple.opacity(0.04)
        case .system: Color.gray.opacity(0.04)
        case .other: Color.clear
        }
    }
}
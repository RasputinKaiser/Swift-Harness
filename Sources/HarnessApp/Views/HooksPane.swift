import SwiftUI

struct HooksPane: View {
    @Environment(HarnessStore.self) private var store
    @State private var selectedEventID: String?

    private let allEvents: [String] = ["PreToolUse", "PostToolUse",
                                      "SessionStart", "UserPromptSubmit",
                                      "PreCompact", "PostCompact", "Stop"]

    var body: some View {
        VStack(spacing: 0) {
            filters
            Divider()
            counters
            Divider()
            eventList
            Divider()
            footer
        }
        .navigationTitle(" Hook Events")
        .task { store.hookEvents.start() }
        .onDisappear { store.hookEvents.detach() }
    }

    // MARK: - Filters

    @ViewBuilder
    private var filters: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(allEvents, id: \.self) { name in
                    EventChip(name: name,
                              selected: store.hookEvents.eventFilter.contains(name))
                        .onTapGesture {
                            if store.hookEvents.eventFilter.contains(name) {
                                store.hookEvents.eventFilter.remove(name)
                            } else {
                                store.hookEvents.eventFilter.insert(name)
                            }
                        }
                }
            }
            TextField("Filter by script name…", text: Binding(
                get: { store.hookEvents.scriptFilter },
                set: { store.hookEvents.scriptFilter = $0 }
            ))
            .textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Outcome counters

    @ViewBuilder
    private var counters: some View {
        let counters = store.hookEvents.outcomeCounters
        HStack(spacing: 12) {
            ForEach(HookEvent.Outcome.allCases, id: \.self) { outcome in
                let n = counters[outcome] ?? 0
                HStack(spacing: 4) {
                    Image(systemName: outcome.icon)
                        .foregroundStyle(Color(outcome.tint))
                    Text("\(n)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .help(outcome.label)
            }
            Spacer()
            Text("\(store.hookEvents.events.count) total")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Event list

    @ViewBuilder
    private var eventList: some View {
        let filtered = store.hookEvents.filteredEvents
        if filtered.isEmpty {
            ContentUnavailableView(
                "No hook events yet",
                systemImage: "waveform",
                description: Text("Fire any tool/migration in NCode — events show up here in real time once ~/.ncode/hook_events.jsonl is being written by the tap-wrapped hooks.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered.reversed()) { e in
                            HookEventRow(event: e)
                                .id(e.id)
                            Divider().opacity(0.4)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .onChange(of: filtered.last?.id) { _, newId in
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
            switch store.hookEvents.status {
            case .idle:
                Label("Idle", systemImage: "moon").foregroundStyle(.secondary)
            case .waiting(let u):
                Label("Waiting for log file…", systemImage: "hourglass")
                    .foregroundStyle(.orange)
                Text(u.lastPathComponent).font(.caption2).foregroundStyle(.tertiary)
            case .tailing(let u):
                Label("Tailing", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                Text(u.lastPathComponent).font(.caption2).foregroundStyle(.tertiary)
            case .failed(let why):
                Label(why, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }
}

private struct EventChip: View {
    let name: String
    let selected: Bool

    var body: some View {
        Text(name)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(selected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1),
                       in: Capsule())
            .foregroundStyle(selected ? Color.accentColor : .secondary)
    }
}

private struct HookEventRow: View {
    let event: HookEvent

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                if !event.stdoutPreview.isEmpty {
                    Text("STDOUT")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(event.stdoutPreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !event.stderrPreview.isEmpty {
                    Text("STDERR")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                    Text(event.stderrPreview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.85))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: event.outcome.icon)
                    .foregroundStyle(Color(event.outcome.tint))
                    .frame(width: 16)
                Text(event.event)
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(.blue)
                Text(event.script)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(event.durationMs)ms")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(event.relativeTime)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
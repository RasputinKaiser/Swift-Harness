import SwiftUI

/// Surfaces mac-cua (computer use) actions from the hook event feed.
/// Shows what the agent is doing on screen — clicks, types, scrolls,
/// screenshots — all in one place.
struct ComputerPane: View {
    @Environment(HarnessStore.self) private var store
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filters
            Divider()
            actionsList
            Divider()
            footer
        }
        .navigationTitle("Computer")
        .task { store.hookEvents.start() }
        .onDisappear { store.hookEvents.detach() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Computer Use")
                    .font(.title3.bold())
                Text("mac-cua actions from the agent — clicks, types, scrolls, screenshots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            outlierSummary
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var outlierSummary: some View {
        let counts = actionCounts
        return HStack(spacing: 10) {
            ForEach(counts, id: \.0) { action, count in
                HStack(spacing: 3) {
                    Image(systemName: iconFor(action))
                        .font(.caption2)
                        .foregroundStyle(tintFor(action))
                    Text("\(count)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .help(action)
            }
        }
    }

    private var filters: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField("Filter by action…", text: $searchText)
                .textFieldStyle(.roundedBorder)
            Spacer()
            Button {
                store.hookEvents.start()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var actionsList: some View {
        let computerActions = filteredActions

        if computerActions.isEmpty {
            ContentUnavailableView(
                "No computer-use actions yet",
                systemImage: "macwindow",
                description: Text("When the agent calls mac-cua tools (click, type, scroll, screenshot), they show up here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(computerActions.reversed()) { e in
                            ComputerActionRow(event: e)
                            Divider().opacity(0.3)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .onChange(of: computerActions.last?.id) { _, newID in
                    if let id = newID {
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("\(filteredActions.count) computer-use actions")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            switch store.hookEvents.status {
            case .tailing: Label("Live", systemImage: "antenna.radiowaves.left.and.right").foregroundStyle(.green).font(.caption2)
            case .waiting: Label("Waiting…", systemImage: "hourglass").foregroundStyle(.orange).font(.caption2)
            case .idle: Label("Idle", systemImage: "moon").foregroundStyle(.secondary).font(.caption2)
            case .failed(let w): Label(w, systemImage: "xmark").foregroundStyle(.red).font(.caption2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }

    // MARK: - Filtering

    private var filteredActions: [HookEvent] {
        store.hookEvents.events.filter { e in
            guard let tn = e.toolName, tn.contains("mac-cua") || tn.contains("mac_cua") else {
                return false
            }
            if searchText.isEmpty { return true }
            return tn.localizedCaseInsensitiveContains(searchText) ||
                   (e.toolInputPreview?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var actionCounts: [(String, Int)] {
        var counts: [String: Int] = [:]
        for e in filteredActions {
            let action = extractAction(e.toolName)
            counts[action, default: 0] += 1
        }
        return counts.sorted(by: { $0.value > $1.value })
    }

    private func extractAction(_ toolName: String?) -> String {
        guard let tn = toolName else { return "unknown" }
        if tn.contains("click") { return "click" }
        if tn.contains("type") { return "type" }
        if tn.contains("scroll") { return "scroll" }
        if tn.contains("screenshot") { return "screenshot" }
        if tn.contains("press_key") { return "keypress" }
        if tn.contains("drag") { return "drag" }
        if tn.contains("set_value") { return "set_value" }
        return "other"
    }

    private func iconFor(_ action: String) -> String {
        switch action {
        case "click": "hand.tap.fill"
        case "type": "keyboard.fill"
        case "scroll": "arrow.up.arrow.down"
        case "screenshot": "camera.fill"
        case "keypress": "command"
        case "drag": "hand.draw.fill"
        case "set_value": "text.cursor"
        default: "circle"
        }
    }

    private func tintFor(_ action: String) -> Color {
        switch action {
        case "click": .blue
        case "type": .green
        case "scroll": .orange
        case "screenshot": .purple
        case "keypress": .indigo
        case "drag": .pink
        default: .secondary
        }
    }
}

private struct ComputerActionRow: View {
    let event: HookEvent

    var body: some View {
        let action = extractAction(event.toolName)
        DisclosureGroup {
            detailView
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconFor(action))
                    .foregroundStyle(tintFor(action))
                    .frame(width: 16)
                Text(event.toolName ?? "?")
                    .font(.system(.caption, design: .monospaced))
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
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var detailView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let input = event.toolInputPreview, !input.isEmpty {
                Text("Input")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(input)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            if !event.stdoutPreview.isEmpty {
                Text("Hook Output")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(event.stdoutPreview.prefix(400))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 4)
    }

    private func extractAction(_ toolName: String?) -> String {
        guard let tn = toolName else { return "unknown" }
        if tn.contains("click") { return "click" }
        if tn.contains("type") { return "type" }
        if tn.contains("scroll") { return "scroll" }
        if tn.contains("screenshot") { return "screenshot" }
        if tn.contains("press_key") { return "keypress" }
        if tn.contains("drag") { return "drag" }
        if tn.contains("set_value") { return "set_value" }
        return "other"
    }

    private func iconFor(_ action: String) -> String {
        switch action {
        case "click": "hand.tap.fill"
        case "type": "keyboard.fill"
        case "scroll": "arrow.up.arrow.down"
        case "screenshot": "camera.fill"
        case "keypress": "command"
        case "drag": "hand.draw.fill"
        case "set_value": "text.cursor"
        default: "circle"
        }
    }

    private func tintFor(_ action: String) -> Color {
        switch action {
        case "click": .blue
        case "type": .green
        case "scroll": .orange
        case "screenshot": .purple
        case "keypress": .indigo
        case "drag": .pink
        default: .secondary
        }
    }
}
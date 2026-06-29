import SwiftUI

struct AgentsPane: View {
    @Environment(HarnessStore.self) private var store
    @State private var selectedAgent: SubagentStore.SubagentRun?
    @State private var searchText = ""
    @State private var showOnlyRunning = false

    var body: some View {
        NavigationSplitView {
            list
                .navigationTitle("Agents")
                .navigationSubtitle("\(store.subagents.subagents.count) runs")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            store.subagents.refresh()
                        } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    }
                }
        } detail: {
            if let agent = selectedAgent,
               let url = URL(string: "file://\(agent.transcriptPath)") {
                AgentTranscriptView(transcriptURL: url, agent: agent)
            } else {
                ContentUnavailableView(
                    "Select a subagent run",
                    systemImage: "person.crop.badge.checkmark",
                    description: Text("Pick a subagent transcript on the left to view its activity.")
                )
            }
        }
        .task {
            if store.subagents.subagents.isEmpty {
                store.subagents.refresh()
            }
        }
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        let filtered = store.subagents.subagents.filter { agent in
            (showOnlyRunning ? agent.status == .running : true) &&
            (searchText.isEmpty ||
             agent.agentType.localizedCaseInsensitiveContains(searchText) ||
             agent.description.localizedCaseInsensitiveContains(searchText) ||
             agent.id.localizedCaseInsensitiveContains(searchText))
        }

        if filtered.isEmpty {
            ContentUnavailableView(
                "No subagent runs",
                systemImage: "person.crop.badge.checkmark",
                description: Text("Dispatch an escalate/repo-scout/test-author agent and they'll show up here.")
            )
        } else {
            List(selection: $selectedAgent) {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.tertiary)
                        TextField("Filter by agent type…", text: $searchText)
                            .textFieldStyle(.plain)
                        Toggle(isOn: $showOnlyRunning) {
                            Text("Running only")
                                .font(.caption2)
                        }
                        .toggleStyle(.checkbox)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                Section("Runs (\(filtered.count))") {
                    ForEach(filtered) { agent in
                        AgentRow(agent: agent).tag(agent)
                    }
                }
                if !store.subagents.byType.isEmpty {
                    Section("By Type") {
                        ForEach(store.subagents.byType, id: \.type) { entry in
                            HStack {
                                Image(systemName: "person.2.fill")
                                    .foregroundStyle(.purple)
                                    .font(.caption)
                                Text(entry.type)
                                    .font(.caption.monospaced())
                                Spacer()
                                Text("\(entry.count)")
                                    .font(.caption2.bold().monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

private struct AgentRow: View {
    let agent: SubagentStore.SubagentRun

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: agent.status.icon)
                .foregroundStyle(Color(agent.status.tint))
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.shortAgentType)
                        .font(.callout.weight(.medium))
                    Text(agent.status.label)
                        .font(.caption2.bold())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(agent.status == .running ? Color.green.opacity(0.15) : Color.gray.opacity(0.1),
                                   in: Capsule())
                        .foregroundStyle(Color(agent.status.tint))
                }
                Text(agent.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    Text("\(agent.lineCount) lines")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(agent.lastModified.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AgentTranscriptView: View {
    let transcriptURL: URL
    let agent: SubagentStore.SubagentRun
    @State private var lines: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.prefix(300))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .task { await loadTranscript() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.badge.checkmark")
                    .foregroundStyle(.purple)
                Text(agent.shortAgentType)
                    .font(.headline)
                Text(agent.status.label)
                    .font(.caption2.bold())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(agent.status == .running ? Color.green.opacity(0.15) : Color.gray.opacity(0.1),
                               in: Capsule())
                    .foregroundStyle(Color(agent.status.tint))
                Spacer()
                Text("\(agent.lineCount) lines")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(agent.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(agent.sessionID.prefix(8))…")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func loadTranscript() async {
        guard let content = try? String(contentsOf: transcriptURL, encoding: .utf8) else { return }
        let rawLines = content.split(separator: "\n").map(String.init)
        // Parse JSONL and extract readable text from each line
        lines = rawLines.compactMap { line in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let type = (json["type"] as? String) ?? "?"
            let ts = ((json["timestamp"] as? String) ?? "").prefix(19)
            switch type {
            case "user":
                if let msg = json["message"] as? [String: Any],
                   let content = msg["content"] as? String {
                    return "[\(ts)] user: \(content.prefix(200))"
                }
                if let msg = json["message"] as? [String: Any],
                   let arr = msg["content"] as? [[String: Any]] {
                    let text = arr.compactMap { $0["text"] as? String }.joined(separator: " ")
                    return "[\(ts)] user: \(text.prefix(200))"
                }
                return "[\(ts)] user"
            case "assistant":
                if let msg = json["message"] as? [String: Any],
                   let arr = msg["content"] as? [[String: Any]] {
                    let texts = arr.compactMap { block -> String? in
                        if block["type"] as? String == "text", let t = block["text"] as? String { return t }
                        if block["type"] as? String == "tool_use", let n = block["name"] as? String {
                            return "[tool: \(n)]"
                        }
                        return nil
                    }
                    return "[\(ts)] assistant: \(texts.joined(separator: " ").prefix(200))"
                }
                return "[\(ts)] assistant"
            default:
                return "[\(ts)] \(type)"
            }
        }
    }
}
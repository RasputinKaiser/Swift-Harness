import SwiftUI

/// Automation management pane — surfaces MCP servers and scheduled tasks
/// in one place. Two Tier 4 gaps closed: MCP server browser + scheduled task
/// visualizer.
struct AutomationPane: View {
    @Environment(HarnessStore.self) private var store
    @State private var mcps: [MCPServerInfo] = []
    @State private var tasks: [ScheduledTaskInfo] = []
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                mcpSection
                scheduledTaskSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Automation")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: loadAll) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { loadAll() }
    }

    // MARK: - MCP Servers

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("MCP Servers", systemImage: "server.rack")
                .font(.headline)
            if mcps.isEmpty {
                Text("No MCP servers configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(mcps, id: \.name) { mcp in
                    MCPServerRow(server: mcp)
                }
            }
        }
    }

    private var scheduledTaskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Scheduled Tasks", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            if tasks.isEmpty {
                Text("No scheduled tasks found. The weekly self-improvement sweep cron may have expired (7-day auto-expiry). Re-create it with install.sh --install-cron.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 400, alignment: .leading)
            } else {
                ForEach(tasks, id: \.id) { task in
                    ScheduledTaskRow(task: task)
                }
            }
        }
    }

    // MARK: - Loaders (run once on appear + on Refresh — not on every render)

    private func loadAll() {
        loadMCPs()
        loadTasks()
    }

    private func loadMCPs() {
        var servers: [MCPServerInfo] = []
        // From ~/.ncode/.config.json (NCode managed)
        let configURL = HarnessClient.ncodeDir.appendingPathComponent(".config.json", conformingTo: .text)
        if let data = try? Data(contentsOf: configURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let mcpServers = json["mcpServers"] as? [String: Any] {
            for (name, cfg) in mcpServers {
                if let cfgDict = cfg as? [String: Any] {
                    servers.append(MCPServerInfo(
                        name: name,
                        command: (cfgDict["command"] as? String) ?? "?",
                        type: (cfgDict["type"] as? String) ?? "stdio",
                        source: "managed",
                        args: cfgDict["args"] as? [String] ?? []
                    ))
                }
            }
        }
        // From settings.local.json (user-added)
        let settingsURL = HarnessClient.ncodeDir.appendingPathComponent("settings.local.json", conformingTo: .text)
        if let data = try? Data(contentsOf: settingsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let mcpServers = json["mcpServers"] as? [String: Any] {
            for (name, cfg) in mcpServers {
                if let cfgDict = cfg as? [String: Any],
                   !servers.contains(where: { $0.name == name }) {
                    servers.append(MCPServerInfo(
                        name: name,
                        command: (cfgDict["command"] as? String) ?? "?",
                        type: (cfgDict["type"] as? String) ?? "stdio",
                        source: "user-local",
                        args: cfgDict["args"] as? [String] ?? []
                    ))
                }
            }
        }
        mcps = servers.sorted(by: { $0.name < $1.name })
    }

    private func loadTasks() {
        let url = HarnessClient.ncodeDir.appendingPathComponent("scheduled_tasks.json", conformingTo: .text)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            tasks = []
            return
        }
        var found: [ScheduledTaskInfo] = []
        if let arr = json["tasks"] as? [[String: Any]] {
            for dict in arr {
                found.append(ScheduledTaskInfo(
                    id: (dict["id"] as? String) ?? UUID().uuidString,
                    cron: (dict["cron"] as? String) ?? "?",
                    prompt: (dict["prompt"] as? String)?.prefix(120).description ?? "",
                    recurring: (dict["recurring"] as? Bool) ?? false,
                    durable: (dict["durable"] as? Bool) ?? false
                ))
            }
        }
        if found.isEmpty {
            for (key, val) in json {
                if let dict = val as? [String: Any] {
                    found.append(ScheduledTaskInfo(
                        id: key,
                        cron: (dict["cron"] as? String) ?? "?",
                        prompt: (dict["prompt"] as? String)?.prefix(120).description ?? "",
                        recurring: (dict["recurring"] as? Bool) ?? false,
                        durable: (dict["durable"] as? Bool) ?? false
                    ))
                }
            }
        }
        tasks = found
    }
}

struct MCPServerInfo: Hashable {
    let name: String
    let command: String
    let type: String
    let source: String  // "managed" or "user-local"
    let args: [String]

    var shortCommand: String {
        let parts = command.split(separator: "/")
        return parts.last.map(String.init) ?? command
    }
    var argsPreview: String {
        args.joined(separator: " ").prefix(80).description
    }
}

struct ScheduledTaskInfo: Identifiable, Hashable {
    let id: String
    let cron: String
    let prompt: String
    let recurring: Bool
    let durable: Bool

    /// Cached parsed cron expression. nil if malformed.
    var expression: CronExpression? { CronExpression.parse(cron) }
    var humanSchedule: String { expression?.humanDescription ?? cron }
    var nextFire: Date? { expression?.nextFire(after: Date()) }
    var nextFireRelative: String? {
        guard let nf = nextFire else { return nil }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: nf, relativeTo: Date())
    }
}

private struct MCPServerRow: View {
    let server: MCPServerInfo
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Command: \(server.command)")
                    .font(.system(.caption, design: .monospaced))
                if !server.args.isEmpty {
                    Text("Args: \(server.argsPreview)")
                        .font(.system(.caption, design: .monospaced))
                }
                Text("Type: \(server.type)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption2)
                Text(server.name)
                    .font(.system(.callout, design: .monospaced))
                Spacer()
                Text(server.source)
                    .font(.caption2.bold())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(server.source == "managed" ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15),
                               in: Capsule())
                    .foregroundStyle(server.source == "managed" ? .blue : .purple)
                Text(server.shortCommand)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct ScheduledTaskRow: View {
    let task: ScheduledTaskInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: task.recurring ? "arrow.triangle.2.circlepath" : "play.circle")
                    .foregroundStyle(task.durable ? .green : .orange)
                    .font(.caption)
                Text(task.humanSchedule)
                    .font(.system(.callout, design: .monospaced))
                Spacer()
                if task.durable {
                    Label("durable", systemImage: "externaldrive.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                }
                if !task.recurring {
                    Label("one-shot", systemImage: "1.circle")
                        .font(.caption2.bold())
                        .foregroundStyle(.purple)
                }
            }
            if let nf = task.nextFire, let rel = task.nextFireRelative {
                HStack(spacing: 4) {
                    Image(systemName: "clock.badge")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("next \(rel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(nf.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("invalid cron expression")
                    .font(.caption2.italic())
                    .foregroundStyle(.red)
            }
            Text(task.prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
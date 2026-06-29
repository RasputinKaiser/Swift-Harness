import SwiftUI

/// Telemetry dashboard — aggregates session usage data from
/// ~/.ncode/usage-data/session-meta/*.json and shows
/// trends across sessions: token usage, tool counts, durations,
/// friction/outcomes.
struct TelemetryPane: View {
    @State private var sessions: [SessionTelemetry] = []
    @State private var isLoading = true

    var body: some View {
        DensePaneScaffold {
            header
            summaryCards
            toolUsageChart
            recentSessionsList
        }
        .navigationTitle("Telemetry")
        .task {
            // Guard: only load if not already loaded — avoids re-reading all
            // session metadata files from disk on every pane switch.
            if sessions.isEmpty { await loadSessions() }
        }
    }

    private var header: some View {
        PaneHeader("NCode Usage Telemetry",
                    systemImage: "chart.xyaxis.line",
                    subtitle: "Aggregated from \(sessions.count) sessions in ~/.ncode/usage-data/") {
            Button { Task { await loadSessions() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Summary

    private var summaryCards: some View {
        let totalInput = sessions.map { $0.inputTokens }.reduce(0, +)
        let totalOutput = sessions.map { $0.outputTokens }.reduce(0, +)
        let totalDuration = sessions.map { $0.durationMinutes }.reduce(0, +)
        let totalErrors = sessions.map { $0.toolErrors }.reduce(0, +)
        let totalCommits = sessions.map { $0.gitCommits }.reduce(0, +)

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            MetricCard(title: "Sessions", value: "\(sessions.count)",
                        systemImage: "list.bullet.rectangle.fill", tint: .blue)
            MetricCard(title: "Input Tokens", value: formatNum(totalInput),
                        systemImage: "arrow.down.circle.fill", tint: .purple)
            MetricCard(title: "Output Tokens", value: formatNum(totalOutput),
                        systemImage: "arrow.up.circle.fill", tint: .green)
            MetricCard(title: "Total Time", value: "\(totalDuration)m",
                        systemImage: "clock.fill", tint: .orange)
            MetricCard(title: "Tool Errors", value: "\(totalErrors)",
                        systemImage: "exclamationmark.triangle.fill",
                        tint: totalErrors > 0 ? .red : .secondary)
            MetricCard(title: "Git Commits", value: "\(totalCommits)",
                        systemImage: "person.crop.circle.badge.checkmark", tint: .indigo)
        }
    }

    // MARK: - Tool usage

    private var toolUsageChart: some View {
        let toolTotals = aggregateTools()
        let maxCount = toolTotals.values.max() ?? 1

        return VStack(alignment: .leading, spacing: 8) {
            Text("Tool Usage")
                .font(.headline)
            ForEach(toolTotals.sorted(by: { $0.value > $1.value }).prefix(10), id: \.key) { tool, count in
                HStack(spacing: 8) {
                    Text(tool)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 80, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor(for: tool))
                            .frame(width: max(geo.size.width * CGFloat(count) / CGFloat(maxCount), 4))
                    }
                    .frame(height: 14)
                    Text("\(count)")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Recent sessions

    private var recentSessionsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Sessions")
                .font(.headline)
            ForEach(sessions.prefix(15)) { s in
                SessionTelemetryRow(session: s)
            }
        }
    }

    // MARK: - Helpers

    private func loadSessions() async {
        isLoading = true
        defer { isLoading = false }

        let dir = HarnessClient.ncodeDir
            .appendingPathComponent("usage-data/session-meta", conformingTo: .directory)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }

        var loaded: [SessionTelemetry] = []
        for file in entries where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file) else { continue }
            let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                loaded.append(SessionTelemetry(from: json, modifiedAt: mtime))
            }
        }
        sessions = loaded.sorted(by: { $0.modifiedAt > $1.modifiedAt })
    }

    private func aggregateTools() -> [String: Int] {
        var totals: [String: Int] = [:]
        for s in sessions {
            for (tool, count) in s.toolCounts {
                totals[tool, default: 0] += count
            }
        }
        return totals
    }

    private func barColor(for tool: String) -> Color {
        switch tool {
        case "Bash": .blue
        case "Read", "Glob", "Grep": .green
        case "Edit", "Write", "MultiEdit": .orange
        case "Agent": .purple
        case "WebFetch", "WebSearch": .teal
        default: .secondary
        }
    }

    private func formatNum(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

struct SessionTelemetry: Identifiable {
    let id: String
    let projectPath: String
    let startTime: String
    let durationMinutes: Int
    let userMessages: Int
    let assistantMessages: Int
    let toolCounts: [String: Int]
    let inputTokens: Int
    let outputTokens: Int
    let toolErrors: Int
    let gitCommits: Int
    let gitPushes: Int
    let languages: [String: Int]
    let linesAdded: Int
    let linesRemoved: Int
    let usesMCP: Bool
    let usesAgent: Bool
    let modifiedAt: Date

    init(from json: [String: Any], modifiedAt: Date) {
        id = (json["session_id"] as? String) ?? UUID().uuidString
        projectPath = (json["project_path"] as? String) ?? "?"
        startTime = (json["start_time"] as? String) ?? "?"
        durationMinutes = (json["duration_minutes"] as? Int) ?? 0
        userMessages = (json["user_message_count"] as? Int) ?? 0
        assistantMessages = (json["assistant_message_count"] as? Int) ?? 0
        toolCounts = (json["tool_counts"] as? [String: Int]) ?? [:]
        inputTokens = (json["input_tokens"] as? Int) ?? 0
        outputTokens = (json["output_tokens"] as? Int) ?? 0
        toolErrors = (json["tool_errors"] as? Int) ?? 0
        gitCommits = (json["git_commits"] as? Int) ?? 0
        gitPushes = (json["git_pushes"] as? Int) ?? 0
        languages = (json["languages"] as? [String: Int]) ?? [:]
        linesAdded = (json["lines_added"] as? Int) ?? 0
        linesRemoved = (json["lines_removed"] as? Int) ?? 0
        usesMCP = (json["uses_mcp"] as? Bool) ?? false
        usesAgent = (json["uses_task_agent"] as? Bool) ?? false
        self.modifiedAt = modifiedAt
    }

    var projectDisplayName: String {
        let parts = projectPath.split(separator: "/")
        return parts.last.map(String.init) ?? projectPath
    }

    var relativeTime: String {
        modifiedAt.formatted(.relative(presentation: .named))
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundStyle(tint)
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(value)
                .font(.system(.title, design: .rounded).bold())
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SessionTelemetryRow: View {
    let session: SessionTelemetry

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(session.projectDisplayName)
                        .font(.callout.weight(.medium))
                    if session.usesAgent {
                        Image(systemName: "person.2.fill").font(.caption2).foregroundStyle(.purple)
                    }
                    if session.usesMCP {
                        Image(systemName: "server.rack").font(.caption2).foregroundStyle(.blue)
                    }
                    if session.gitCommits > 0 {
                        Badge(label: "commit", value: "\(session.gitCommits)", tint: .green)
                    }
                    if session.toolErrors > 0 {
                        Badge(label: "errors", value: "\(session.toolErrors)", tint: .red)
                    }
                    Spacer()
                    Text(session.relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 8) {
                    MiniStat("in", formatTokens(session.inputTokens), .purple)
                    MiniStat("out", formatTokens(session.outputTokens), .green)
                    MiniStat("dur", "\(session.durationMinutes)m", .orange)
                    MiniStat("tools", "\(session.toolCounts.values.reduce(0, +))", .blue)
                    MiniStat("±", "+\(session.linesAdded)/-\(session.linesRemoved)", .secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

private struct Badge: View {
    let label: String
    let value: String
    let tint: Color
    var body: some View {
        HStack(spacing: 2) {
            Text(label).font(.caption2)
            Text(value).font(.caption2.bold().monospacedDigit())
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(tint.opacity(0.15), in: Capsule())
        .foregroundStyle(tint)
    }
}

private struct MiniStat: View {
    let label: String
    let value: String
    let tint: Color
    init(_ label: String, _ value: String, _ tint: Color) {
        self.label = label
        self.value = value
        self.tint = tint
    }
    var body: some View {
        HStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(tint)
            Text(value).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
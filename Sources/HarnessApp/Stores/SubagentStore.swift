import Foundation
import Observation

/// `@Observable` catalog of discovered subagent runs across all projects.
///
/// Scans ~/.ncode/projects/*/<sessionID>/subagents/ for agent-*.jsonl files
/// and their .meta.json companions. Exposes a flat list of all subagent runs
/// with metadata + last-activity timestamp.
@Observable
final class SubagentStore {

    private(set) var subagents: [SubagentRun] = []
    private(set) var lastError: String?
    private(set) var lastRefresh: Date?

    struct SubagentRun: Identifiable, Hashable {
        let id: String              // agentId from transcript
        let agentType: String       // from meta.json
        let description: String    // from meta.json
        let transcriptPath: String
        let metaPath: String
        let sessionID: String       // parent session
        let projectPath: String     // encoded project path
        let lastModified: Date
        let lineCount: Int

        var displayName: String { String(id.split(separator: "-").prefix(3).joined(separator: "-")) }
        var shortAgentType: String {
            agentType
                .replacingOccurrences(of: "Self-Improvement-Plugin:", with: "")
                .replacingOccurrences(of: "harness-" + "self-improvement:", with: "")
        }

        var status: RunStatus {
            // "recent" if modified in last 5 min — likely still running
            if Date().timeIntervalSince(lastModified) < 300 { return .running }
            return .completed
        }

        enum RunStatus: String, Hashable {
            case running, completed
            var label: String { rawValue.capitalized }
            var icon: String { self == .running ? "circle.fill" : "checkmark.circle.fill" }
            var tint: String { self == .running ? "green" : "secondary" }
        }
    }

    init() {}

    @MainActor
    func refresh() {
        let projectsDir = HarnessClient.home
            .appendingPathComponent(".ncode/projects", conformingTo: .directory)

        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            lastError = "no projects found"
            return
        }

        var found: [SubagentRun] = []
        for projectDir in projectDirs {
            guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }

            // Each project dir contains session subdirs
            guard let sessionDirs = try? FileManager.default.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.isDirectoryKey]
            ) else { continue }

            for sessionDir in sessionDirs where sessionDir.hasDirectoryPath {
                let subagentsDir = sessionDir.appendingPathComponent("subagents", conformingTo: .directory)

                guard let agentFiles = try? FileManager.default.contentsOfDirectory(
                    at: subagentsDir,
                    includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
                ) else { continue }

                for file in agentFiles where file.pathExtension == "jsonl" && file.lastPathComponent.hasPrefix("agent-") {
                    let agentId = file.deletingPathExtension().lastPathComponent
                    let metaPath = subagentsDir.appendingPathComponent("\(agentId).meta.json", conformingTo: .text)

                    var agentType = "unknown"
                    var desc = ""
                    if let metaData = try? Data(contentsOf: metaPath),
                       let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any] {
                        agentType = (meta["agentType"] as? String) ?? "unknown"
                        desc = (meta["description"] as? String) ?? ""
                    }

                    let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey])
                                    .contentModificationDate) ?? Date.distantPast
                    let lineCount = countLines(file)

                    found.append(SubagentRun(
                        id: agentId,
                        agentType: agentType,
                        description: desc,
                        transcriptPath: file.path,
                        metaPath: metaPath.path,
                        sessionID: sessionDir.lastPathComponent,
                        projectPath: projectDir.lastPathComponent,
                        lastModified: mtime,
                        lineCount: lineCount
                    ))
                }
            }
        }

        subagents = found.sorted(by: { $0.lastModified > $1.lastModified })
        lastRefresh = Date()
        lastError = nil
    }

    var runningCount: Int { subagents.filter { $0.status == .running }.count }
    var completedCount: Int { subagents.filter { $0.status == .completed }.count }

    /// Group by agent type for the dashboard.
    var byType: [(type: String, count: Int)] {
        var counts: [String: Int] = [:]
        for s in subagents {
            counts[s.agentType, default: 0] += 1
        }
        return counts.sorted(by: { $0.value > $1.value }).map { (type: $0.key, count: $0.value) }
    }

    private func countLines(_ url: URL) -> Int {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return content.split(separator: "\n").count
    }
}

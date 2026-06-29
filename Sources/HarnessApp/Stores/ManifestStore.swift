import Foundation
import Observation

/// `@Observable` catalog of the installed harness plugin's surfaces —
/// hooks (from hooks.json), agents (from agents/*.md frontmatter), commands
/// (from commands/*.md frontmatter). Pure read; no mutation.
///
/// Reads from the install cache at ~/.ncode/plugins/marketplaces/harness-local/.
@Observable
final class ManifestStore {

    private(set) var hooks: [HookEntry] = []
    private(set) var agents: [AgentEntry] = []
    private(set) var commands: [CommandEntry] = []
    private(set) var pluginMeta: PluginMeta?
    private(set) var lastError: String?
    private(set) var lastRefresh: Date?

    struct HookEntry: Identifiable, Hashable {
        let id: String  // event[matcher]#index
        let event: String
        let matcher: String
        let script: String
        let command: String
        let timeout: Int
        let statusMessage: String?
    }

    struct AgentEntry: Identifiable, Hashable {
        let id: String  // name
        let name: String
        let description: String
        let model: String
        let toolsHint: String?
        let filePath: String
    }

    struct CommandEntry: Identifiable, Hashable {
        let id: String  // name
        let name: String
        let description: String
        let filePath: String
    }

    struct PluginMeta: Hashable {
        let name: String
        let version: String
        let description: String
        let authorName: String
        let license: String
        let hooksCount: Int
        let agentsCount: Int
        let commandsCount: Int
    }

    init() {}

    @MainActor
    func refresh() {
        let pluginRoot = HarnessClient.ncodeDir
            .appendingPathComponent("plugins/marketplaces/harness-local", conformingTo: .directory)
        guard FileManager.default.fileExists(atPath: pluginRoot.path) else {
            lastError = "harness plugin not installed at ~/.ncode/plugins/marketplaces/harness-local/"
            return
        }
        lastError = nil
        hooks = parseHooks(pluginRoot)
        agents = parseAgents(pluginRoot)
        commands = parseCommands(pluginRoot)
        pluginMeta = parsePluginMeta(pluginRoot, hooksCount: hooks.count,
                                      agentsCount: agents.count,
                                      commandsCount: commands.count)
        lastRefresh = Date()
    }

    // MARK: - Parsers

    private func parseHooks(_ root: URL) -> [HookEntry] {
        let url = root.appendingPathComponent("hooks/hooks.json", conformingTo: .text)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooksDict = json["hooks"] as? [String: Any] else {
            return []
        }
        var out: [HookEntry] = []
        for (event, blocks) in hooksDict {
            guard let blockArr = blocks as? [[String: Any]] else { continue }
            for (i, block) in blockArr.enumerated() {
                let matcher = (block["matcher"] as? String) ?? ""
                guard let hookArr = block["hooks"] as? [[String: Any]] else { continue }
                for (j, h) in hookArr.enumerated() {
                    let cmd = (h["command"] as? String) ?? ""
                    let timeout = (h["timeout"] as? Int) ?? 0
                    let status = h["statusMessage"] as? String
                    // Extract script name from command
                    let scriptName = extractScriptName(from: cmd)
                    out.append(HookEntry(
                        id: "\(event)[\(i)][\(j)]",
                        event: event,
                        matcher: matcher,
                        script: scriptName,
                        command: cmd,
                        timeout: timeout,
                        statusMessage: status
                    ))
                }
            }
        }
        return out.sorted { $0.event < $1.event }
    }

    private func extractScriptName(from cmd: String) -> String {
        // Look for scripts/<name>.py or scripts/<name>.sh
        if let r = cmd.range(of: "scripts/[^\\s\"']+\\.(py|sh)", options: .regularExpression) {
            var name = String(cmd[r])
            if name.hasPrefix("scripts/") { name.removeFirst("scripts/".count) }
            return name
        }
        return "?"
    }

    private func parseAgents(_ root: URL) -> [AgentEntry] {
        let dir = root.appendingPathComponent("agents", conformingTo: .directory)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        var out: [AgentEntry] = []
        for file in entries where file.pathExtension == "md" {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let (fm, _) = parseFrontmatter(content)
            let name = fm["name"] ?? file.deletingPathExtension().lastPathComponent
            let desc = fm["description"] ?? ""
            let model = fm["model"] ?? "?"
            let tools = fm["tools"]
            out.append(AgentEntry(
                id: name,
                name: name,
                description: desc,
                model: model,
                toolsHint: tools,
                filePath: file.path
            ))
        }
        return out.sorted { $0.name < $1.name }
    }

    private func parseCommands(_ root: URL) -> [CommandEntry] {
        let dir = root.appendingPathComponent("commands", conformingTo: .directory)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        var out: [CommandEntry] = []
        for file in entries where file.pathExtension == "md" {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let (fm, _) = parseFrontmatter(content)
            let name = fm["name"] ?? file.deletingPathExtension().lastPathComponent
            let desc = fm["description"] ?? ""
            out.append(CommandEntry(
                id: name,
                name: name,
                description: desc,
                filePath: file.path
            ))
        }
        return out.sorted { $0.name < $1.name }
    }

    private func parsePluginMeta(_ root: URL, hooksCount: Int, agentsCount: Int, commandsCount: Int) -> PluginMeta? {
        let url = root.appendingPathComponent(".codex-plugin/plugin.json", conformingTo: .text)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return PluginMeta(
            name: (json["name"] as? String) ?? "?",
            version: (json["version"] as? String) ?? "?",
            description: (json["description"] as? String) ?? "",
            authorName: ((json["author"] as? [String: Any])?["name"] as? String) ?? "?",
            license: (json["license"] as? String) ?? "?",
            hooksCount: hooksCount,
            agentsCount: agentsCount,
            commandsCount: commandsCount
        )
    }

    /// Parse YAML-ish frontmatter (between --- delimiters). Good enough for
    /// harness plugin's flat key: value format.
    private func parseFrontmatter(_ text: String) -> ([String: String], String) {
        guard text.hasPrefix("---") else { return ([:], text) }
        let lines = text.split(separator: "\n", maxSplits: 100, omittingEmptySubsequences: false)
        var inFM = false
        var fm: [String: String] = [:]
        var body = ""
        var fmEnded = false
        for line in lines.dropFirst() {  // skip opening ---
            if line.hasPrefix("---") {
                fmEnded = true
                continue
            }
            if !fmEnded {
                if let colonIdx = line.firstIndex(of: ":") {
                    let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                    var value = String(line[line.index(after: colonIdx)...])
                        .trimmingCharacters(in: .whitespaces)
                    // strip leading/trailing quotes
                    if value.hasPrefix("\"") && value.hasSuffix("\"") {
                        value = String(value.dropFirst().dropLast())
                    }
                    fm[key] = value
                }
            } else {
                body += line + "\n"
            }
        }
        return (fm, body)
    }
}
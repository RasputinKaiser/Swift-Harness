import Foundation
import UniformTypeIdentifiers

/// Static service: shells out to ~/.ncode/scripts/*.py and reads harness state from disk.
/// All blocking work happens on a detached Task; UI never blocks.
enum HarnessClient {

    // MARK: - Subprocess

    struct RunResult {
        let exitCode: Int
        let stdout: String
        let stderr: String
        let duration: TimeInterval
        var ok: Bool { exitCode == 0 }
    }

    static func run(command: [String], cwd: URL?) async -> RunResult {
        precondition(!command.isEmpty, "command must have at least one element")
        var resolved = command
        resolved[0] = resolveExecutable(command[0])
        let start = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolved[0])
        process.arguments = Array(resolved.dropFirst())
        if let cwd { process.currentDirectoryURL = cwd }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            return RunResult(
                exitCode: Int(process.terminationStatus),
                stdout: String(data: outData, encoding: .utf8) ?? "",
                stderr: String(data: errData, encoding: .utf8) ?? "",
                duration: Date().timeIntervalSince(start)
            )
        } catch {
            return RunResult(
                exitCode: -1,
                stdout: "",
                stderr: error.localizedDescription,
                duration: Date().timeIntervalSince(start)
            )
        }
    }

    /// Resolve a bare command name (e.g. "python3", "bash") to a full path via
    /// the user's PATH. `Process.executableURL` doesn't search PATH unlike bash.
    static func resolveExecutable(_ name: String) -> String {
        if name.hasPrefix("/") || name.contains("/") {
            return name  // already a path
        }
        let candidates = [
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/Users/\(NSUserName())/.homebrew/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)",
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            for dir in envPath.split(separator: ":") {
                let p = "\(dir)/\(name)"
                if FileManager.default.isExecutableFile(atPath: p) {
                    return p
                }
            }
        }
        return name
    }

    // MARK: - Harness paths

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var ncodeDir: URL { home.appendingPathComponent(".ncode", conformingTo: .directory) }
    static var scriptsDir: URL { ncodeDir.appendingPathComponent("scripts", conformingTo: .directory) }
    static var improvementsPath: URL { ncodeDir.appendingPathComponent("improvements.md", conformingTo: .text) }
    static var snapshotsDir: URL { ncodeDir.appendingPathComponent("backups/snapshots", conformingTo: .directory) }
    static var continuityDir: URL { ncodeDir.appendingPathComponent("continuity", conformingTo: .directory) }

    static func scriptPath(_ name: String) -> URL {
        scriptsDir.appendingPathComponent(name, conformingTo: .text)
    }

    // MARK: - Harness queries

    /// Disk-based read of run_tests.py last result. Avoids re-running tests to populate status.
    static func parseTestCountFromStdout(_ s: String) -> (passed: Int, failed: Int)? {
        // Format from run_tests.py: "results: <pass> pass, <fail> fail"
        guard let range = s.range(of: "results:", options: .backwards) else { return nil }
        let tail = s[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #/(\d+)\s+pass,\s*(\d+)\s+fail/#
        guard let m = tail.firstMatch(of: pattern) else { return nil }
        return (Int(m.1) ?? 0, Int(m.2) ?? 0)
    }

    static func latestImprovementEntry() -> String? {
        guard let content = try? String(contentsOf: improvementsPath, encoding: .utf8) else { return nil }
        guard let range = content.range(of: "## Self-correction", options: .backwards) else { return nil }
        let tail = content[range.lowerBound...]
        if let nextRange = tail.range(of: "\n## ", options: .literal,
                                       range: tail.index(after: range.lowerBound)..<tail.endIndex) {
            return String(tail[range.lowerBound..<nextRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(tail).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func latestImprovementTimestamp() -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: improvementsPath.path),
              let mtime = attrs[.modificationDate] as? Date else { return nil }
        return mtime
    }

    static func snapshotCount() -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: snapshotsDir, includingPropertiesForKeys: nil) else { return 0 }
        return entries.filter { $0.hasDirectoryPath }.count
    }

    static func continuityCount() -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: continuityDir, includingPropertiesForKeys: nil) else { return 0 }
        return entries.count
    }
}

/// Lightweight Memory Fabric count fetch. Decoupled from the full MemoryClient.
enum MemoryFabricClient {

    static func count(scope: String) async -> Int {
        guard let cli = findCLI() else { return 0 }
        let r = await HarnessClient.run(
            command: ["python3", cli, "search", "--query", "", "--scope", scope, "--limit", "1"],
            cwd: HarnessClient.ncodeDir
        )
        guard r.ok, let data = r.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let count = json["count"] as? Int else { return 0 }
        return count
    }

    static func recent(scope: String, limit: Int = 10) async -> [Record] {
        guard let cli = findCLI() else { return [] }
        let r = await HarnessClient.run(
            command: ["python3", cli, "search",
                     "--query", "outcome session learning work",
                     "--scope", scope,
                     "--provenance-type", "source_backed_agent_run",
                     "--limit", String(limit)],
            cwd: HarnessClient.ncodeDir
        )
        guard r.ok, let data = r.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = json["records"] as? [[String: Any]] else { return [] }
        return records.map(Record.init(from:))
    }

    static func findCLI() -> String? {
        let fm = FileManager.default
        let cacheRoot = HarnessClient.home
            .appendingPathComponent(".codex/plugins/cache/ralto-local/codex-memory-fabric", conformingTo: .directory)
        guard let entries = try? fm.contentsOfDirectory(atPath: cacheRoot.path) else { return nil }
        let codexStamps = entries.filter { $0.contains("+codex") }.sorted()
        for stamp in codexStamps.reversed() {
            let scripts = cacheRoot.appendingPathComponent(stamp, conformingTo: .directory)
                .appendingPathComponent("scripts", conformingTo: .directory)
            let cli = scripts.appendingPathComponent("memory_fabric.py")
            if fm.fileExists(atPath: cli.path) { return cli.path }
        }
        return nil
    }

    struct Record: Identifiable, Hashable {
        let id: String
        let tier: String
        let title: String
        let body: String
        let tags: [String]
        let confidence: String?
        let createdAt: String?

        init(from json: [String: Any]) {
            id = json["id"] as? String ?? UUID().uuidString
            tier = json["tier"] as? String ?? "?"
            title = json["title"] as? String ?? ""
            body = json["body"] as? String ?? ""
            tags = json["tags"] as? [String] ?? []
            confidence = json["confidence"] as? String
            createdAt = (json["created_at"] as? String)?.prefix(16).description
        }
    }
}
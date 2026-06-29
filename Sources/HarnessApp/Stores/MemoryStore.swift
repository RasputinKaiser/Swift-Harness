import Foundation
import Observation

/// `@Observable` wrapper around the Memory Fabric CLI. Supports live query,
/// tier filter, sort, and archive-as-side-log (writes to
/// ~/.ncode/memory_archive.jsonl — only the app reads this).
@Observable
final class MemoryStore {

    private(set) var records: [MemoryRecord] = []
    private(set) var totalCount: Int = 0
    private(set) var lastQuery: String = ""
    private(set) var lastError: String?
    private(set) var isLoading = false
    private(set) var lastRefresh: Date?

    /// User-editable filters
    var query: String = "" { didSet { Task { await search() } } }
    var selectedTiers: Set<String> = [] { didSet { Task { await search() } } }
    var sort: MemorySort = .score { didSet { Task { await search() } } }
    var showArchived: Bool = false { didSet { Task { await search() } } }

    init() {}

    @MainActor
    func bootstrap() async {
        if records.isEmpty {
            await search()
        }
    }

    @MainActor
    func search() async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil
        lastQuery = query

        guard let cli = MemoryFabricClient.findCLI() else {
            lastError = "memory_fabric.py CLI not found under ~/.codex/plugins/cache"
            return
        }

        // Build base cmd
        var cmd: [String] = ["python3", cli, "search",
                            "--query", query.isEmpty ? "outcome session learning work harness" : query,
                            "--scope", HarnessClient.ncodeDir.path,
                            "--limit", "50"]
        if !selectedTiers.isEmpty {
            // Take first tier — CLI accepts a single --tier flag
            cmd += ["--tier", selectedTiers.first!]
        }
        if !showArchived {
            cmd += ["--provenance-type", "source_backed_agent_run"]
        }

        // Tunnel through stderr to capture errors without breaking query
        let r = await HarnessClient.run(
            command: cmd,
            cwd: HarnessClient.ncodeDir
        )
        if !r.ok {
            lastError = "search exit \(r.exitCode): \(r.stderr.prefix(160))"
            return
        }

        guard let data = r.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            lastError = "search returned non-JSON output"
            return
        }
        totalCount = json["count"] as? Int ?? 0
        guard let raw = json["records"] as? [[String: Any]] else {
            records = []
            return
        }

        var recs: [MemoryRecord] = []
        for dict in raw {
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let rec = try? JSONDecoder().decode(MemoryRecord.self, from: data) {
                recs.append(rec)
            }
        }
        applySort(to: &recs)
        records = recs
        lastRefresh = Date()
    }

    @MainActor
    func archive(_ record: MemoryRecord) async {
        let path = HarnessClient.ncodeDir.appendingPathComponent("memory_archive.jsonl", conformingTo: .text)
        let entry = """
        {"id":"\(record.id)","archivedAt":"\(ISO8601DateFormatter().string(from: Date()))","title":"\(record.title.replacingOccurrences(of: "\"", with: "\\\""))"}
        """
        do {
            try entry.appending("\n").write(to: path, atomically: true, encoding: .utf8)
        } catch {
            lastError = "archive write failed: \(error.localizedDescription)"
            return
        }
        records.removeAll { $0.id == record.id }
    }

    private func applySort(to recs: inout [MemoryRecord]) {
        switch sort {
        case .recent:
            recs.sort { (l, r) in
                (l.date ?? .distantPast) > (r.date ?? .distantPast)
            }
        case .score:
            recs.sort { (l, r) in
                (l.score ?? 0) > (r.score ?? 0)
            }
        case .confidence:
            let order = ["high": 0, "medium": 1, "low": 2, "unknown": 3]
            recs.sort { (l, r) in
                (order[l.confidence ?? "unknown"] ?? 4) <
                (order[r.confidence ?? "unknown"] ?? 4)
            }
        }
    }

    /// Returns the set of archive IDs from the side log. Used to fade archived
    /// records if `showArchived == true`.
    func archivedIDs() -> Set<String> {
        let path = HarnessClient.ncodeDir.appendingPathComponent("memory_archive.jsonl", conformingTo: .text)
        guard let content = try? String(contentsOf: path, encoding: .utf8) else { return [] }
        var out: Set<String> = []
        for line in content.split(separator: "\n") {
            if let data = line.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = dict["id"] as? String {
                out.insert(id)
            }
        }
        return out
    }
}
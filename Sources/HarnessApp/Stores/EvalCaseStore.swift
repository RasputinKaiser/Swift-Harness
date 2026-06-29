import Foundation
import Observation

/// Discovers eval cases at `~/.ncode/eval/cases/*.json` and seeds a default
/// trio when the directory is empty (process check, quality trivial, quality
/// moderate). Holds the in-memory case list + the most recent run per case
/// (loaded from `~/.ncode/eval/results.jsonl`).
@Observable
final class EvalCaseStore {

    private(set) var cases: [EvalCase] = []
    private(set) var lastRuns: [String: EvalRun] = [:]  // caseId → most recent run
    private(set) var lastError: String?
    private(set) var loadedAt: Date?

    var casesDir: URL {
        HarnessClient.ncodeDir.appendingPathComponent("eval/cases", conformingTo: .directory)
    }
    var resultsPath: URL {
        HarnessClient.ncodeDir.appendingPathComponent("eval/results.jsonl", conformingTo: .text)
    }

    @MainActor
    func refresh() {
        ensureSeeds()
        cases = discoverCases()
        lastRuns = loadLastRuns()
        loadedAt = Date()
    }

    /// Look up a case by id.
    func find(byId id: String) -> EvalCase? {
        cases.first { $0.id == id }
    }

    /// Most recent finished run for a case, if any.
    func lastRun(for caseId: String) -> EvalRun? {
        lastRuns[caseId]
    }

    /// All runs for a case, oldest first (used by per-case trend).
    private(set) var runsByCase: [String: [EvalRun]] = [:]

    /// Last N runs across all cases, oldest-first (used by the header sparkline).
    func recentRuns(limit: Int = 12) -> [EvalRun] {
        var all: [EvalRun] = []
        for runs in runsByCase.values {
            all.append(contentsOf: runs)
        }
        all.sort { (a, b) in
            (a.finishedAt ?? .distantPast) < (b.finishedAt ?? .distantPast)
        }
        return Array(all.suffix(limit))
    }

    // MARK: - Run history

    /// Read ~/.ncode/eval/results.jsonl and bucket runs by caseId, keeping
    /// only the most recent per case. Defensive on malformed lines.
    private func loadLastRuns() -> [String: EvalRun] {
        guard let data = try? Data(contentsOf: resultsPath),
              let text = String(data: data, encoding: .utf8) else {
            return [:]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var byCaseLast: [String: EvalRun] = [:]
        var allByCase: [String: [EvalRun]] = [:]
        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let run = try? decoder.decode(EvalRun.self, from: lineData) else {
                continue
            }
            var arr = allByCase[run.caseId] ?? []
            arr.append(run)
            allByCase[run.caseId] = arr
            // Keep newer runs (later in file = more recent)
            if let existing = byCaseLast[run.caseId],
               let exTime = existing.finishedAt, let newTime = run.finishedAt,
               exTime >= newTime {
                continue
            }
            byCaseLast[run.caseId] = run
        }
        // Sort each case's history oldest-first
        for (cid, runs) in allByCase {
            allByCase[cid] = runs.sorted { (a, b) in
                (a.finishedAt ?? .distantPast) < (b.finishedAt ?? .distantPast)
            }
        }
        runsByCase = allByCase
        return byCaseLast
    }

    // MARK: - Discovery

    private func discoverCases() -> [EvalCase] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: casesDir,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            lastError = "could not read \(casesDir.path)"
            return []
        }
        let decoder = JSONDecoder()
        var found: [EvalCase] = []
        for file in entries where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let c = try? decoder.decode(EvalCase.self, from: data) else {
                continue
            }
            found.append(c)
        }
        return found.sorted(by: { $0.id < $1.id })
    }

    /// Seed the default case trio if no cases exist yet. Idempotent.
    private func ensureSeeds() {
        try? FileManager.default.createDirectory(at: casesDir, withIntermediateDirectories: true)
        guard let existing = try? FileManager.default.contentsOfDirectory(at: casesDir, includingPropertiesForKeys: nil),
              existing.contains(where: { $0.pathExtension == "json" }) else {
            writeSeeds()
            return
        }
    }

    private func writeSeeds() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for seed in EvalCaseStore.defaultSeeds {
            let url = casesDir.appendingPathComponent("\(seed.id).json", conformingTo: .text)
            if let data = try? encoder.encode(seed) {
                try? data.write(to: url)
            }
        }
    }

    static let defaultSeeds: [EvalCase] = [
        EvalCase(
            id: "proc-read-before-edit-001",
            version: 1,
            tier: .process,
            difficulty: .trivial,
            prompt: "Read the file README.md in the current directory, then create a new file called SUMMARY.md containing the first sentence of README.md.",
            timeoutSeconds: 60,
            grading: [
                EvalCheck(kind: .transcriptSequence,
                          arguments: ["first": "Read", "before": "Edit|Write"])
            ],
            passThreshold: 1.0,
            tags: ["process", "read-before-edit"]
        ),
        EvalCase(
            id: "qual-create-file-001",
            version: 1,
            tier: .quality,
            difficulty: .trivial,
            prompt: "Create a file at hello.txt containing exactly the text: hello world",
            timeoutSeconds: 30,
            grading: [
                EvalCheck(kind: .fileExists, arguments: ["path": "hello.txt"]),
                EvalCheck(kind: .grep, arguments: ["path": "hello.txt", "pattern": "hello world"])
            ],
            passThreshold: 1.0,
            tags: ["quality", "file-create"]
        ),
        EvalCase(
            id: "qual-quote-echo-001",
            version: 1,
            tier: .quality,
            difficulty: .trivial,
            prompt: "Run the shell command: echo forty-two. Then create a file called last-echo.txt containing the text you saw printed.",
            timeoutSeconds: 30,
            grading: [
                EvalCheck(kind: .fileExists, arguments: ["path": "last-echo.txt"]),
                EvalCheck(kind: .grep, arguments: ["path": "last-echo.txt", "pattern": "forty-two"])
            ],
            passThreshold: 1.0,
            tags: ["quality", "bash-then-edit"]
        ),
    ]
}
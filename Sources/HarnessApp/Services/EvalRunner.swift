import Foundation
import Observation

/// Runs a single eval case against the live NCode model config in an isolated
/// sandbox cwd, captures the ordered tool_use names from the stream-json
/// transcript, and grades the result via `EvalGrader`.
///
/// One-shot flow:
/// 1. Create sandbox at `~/.ncode/eval/sandboxes/<runId>/`.
/// 2. Spawn ncode with `--print --input-format stream-json --output-format
///    stream-json --include-partial-messages --permission-mode bypassPermissions`.
/// 3. Write one user message line, close stdin (EOF → ncode processes one turn).
/// 4. Read stdout lines until a `result` event arrives, the process exits, or
///    the timeout fires.
/// 5. Extract tool_use names from assistant messages in order.
/// 6. Grade via `EvalGrader.grade(_:sandboxURL:toolSequence:)`.
/// 7. Append the EvalRun to `~/.ncode/eval/results.jsonl`.
/// 8. Sandbox is kept for inspection (not auto-cleaned — small on disk).
@Observable
final class EvalRunner {

    /// Progress callback for live UI updates during a run.
    typealias ProgressHandler = @MainActor (EvalRunProgress) -> Void

    private(set) var isRunning = false
    private(set) var lastRun: EvalRun?
    private(set) var lastError: String?

    var sandboxesDir: URL {
        HarnessClient.ncodeDir.appendingPathComponent("eval/sandboxes", conformingTo: .directory)
    }
    var resultsPath: URL {
        HarnessClient.ncodeDir.appendingPathComponent("eval/results.jsonl", conformingTo: .text)
    }

    /// Run a single case. Returns the finished EvalRun (with score + passed).
    @discardableResult
    func run(case evalCase: EvalCase,
             model: String? = nil,
             progress: ProgressHandler? = nil) async -> EvalRun {
        isRunning = true
        defer { isRunning = false }

        let runId = UUID().uuidString.prefix(8)
        let sandbox = sandboxesDir.appendingPathComponent(String(runId), conformingTo: .directory)
        try? FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)

        var run = EvalRun(caseId: evalCase.id, caseVersion: evalCase.version, model: model)
        await Task { @MainActor in progress?(.started(caseId: evalCase.id, sandbox: sandbox)) }.value

        do {
            let toolSequence = try await spawnNCode(
                prompt: evalCase.prompt,
                cwd: sandbox,
                timeoutSeconds: evalCase.timeoutSeconds,
                progress: progress
            )
            await Task { @MainActor in progress?(.graded(toolCount: toolSequence.count)) }.value

            let (results, score) = EvalGrader.grade(
                evalCase.grading,
                sandboxURL: sandbox,
                toolSequence: toolSequence
            )
            let passed = score >= evalCase.passThreshold
            run = EvalRun(
                caseId: evalCase.id, caseVersion: evalCase.version,
                model: model, sandboxURL: sandbox, finishedAt: Date(),
                score: score, passed: passed, checkResults: results,
                toolCount: toolSequence.count, errorMessage: nil
            )
        } catch {
            run = EvalRun(
                caseId: evalCase.id, caseVersion: evalCase.version,
                model: model, sandboxURL: sandbox, finishedAt: Date(),
                score: 0, passed: false, checkResults: [],
                toolCount: 0, errorMessage: error.localizedDescription
            )
            lastError = error.localizedDescription
        }

        persist(run)
        lastRun = run
        await Task { @MainActor in progress?(.completed(run)) }.value
        return run
    }

    // MARK: - Spawn

    @discardableResult
    private func spawnNCode(prompt: String, cwd: URL, timeoutSeconds: Int,
                            progress: ProgressHandler?) async throws -> [String] {
        let binPath = HarnessClient.home
            .appendingPathComponent(".local/bin/ncode", conformingTo: .text).path
        let resolvedBin = FileManager.default.isExecutableFile(atPath: binPath)
            ? binPath
            : "/usr/local/bin/ncode"
        guard FileManager.default.isExecutableFile(atPath: resolvedBin) else {
            throw EvalError.binaryNotFound(resolvedBin)
        }

        let args = [
            "--print",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--session-id", UUID().uuidString,
            "--permission-mode", "bypassPermissions",
        ]

        let payload: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": prompt],
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        var payloadLine = payloadData
        payloadLine.append(0x0A)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: resolvedBin)
        p.arguments = args
        p.currentDirectoryURL = cwd

        let outPipe = Pipe()
        let inPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = Pipe()
        p.standardInput = inPipe

        let toolSequence = ToolSequenceCollector()
        let buf = LineCollector { [weak toolSequence] line in
            toolSequence?.process(line)
        }
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            buf.append(data)
        }

        try p.run()
        try inPipe.fileHandleForWriting.write(contentsOf: payloadLine)
        try? inPipe.fileHandleForWriting.close()

        let timeoutNanos = UInt64(timeoutSeconds) * 1_000_000_000
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        var finished = false

        return try await withTaskCancellationHandler {
            while !finished {
                try Task.checkCancellation()
                if Date() > deadline {
                    p.terminate()
                    throw EvalError.timeout
                }
                if toolSequence.resultSeen {
                    finished = true
                    break
                }
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms poll
            }
            p.terminate()
            return toolSequence.tools
        } onCancel: {
            p.terminate()
        }
    }

    // MARK: - Persistence

    private func persist(_ run: EvalRun) {
        try? FileManager.default.createDirectory(
            at: resultsPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(run) {
            var line = data
            line.append(0x0A)
            if let handle = try? FileHandle(forWritingTo: resultsPath) {
                handle.seekToEndOfFile()
                handle.write(line)
                try? handle.close()
            } else {
                try? line.write(to: resultsPath)
            }
        }
    }
}

enum EvalError: LocalizedError {
    case binaryNotFound(String)
    case timeout
    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let p): "ncode binary not found at \(p)"
        case .timeout: "case timed out"
        }
    }
}

/// Progress events surfaced to the UI during a run.
enum EvalRunProgress {
    case started(caseId: String, sandbox: URL)
    case graded(toolCount: Int)
    case completed(EvalRun)
}

/// Collects tool_use names in order from stream-json lines. Thread-safe via
/// the consuming pipe's serial readabilityHandler queue.
private final class ToolSequenceCollector: @unchecked Sendable {
    private(set) var tools: [String] = []
    private(set) var resultSeen = false

    func process(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let type = (json["type"] as? String) ?? ""
        if type == "assistant",
           let msg = json["message"] as? [String: Any],
           let blocks = msg["content"] as? [[String: Any]] {
            for block in blocks {
                if (block["type"] as? String) == "tool_use",
                   let name = block["name"] as? String {
                    tools.append(name)
                }
            }
        }
        if type == "result" { resultSeen = true }
    }
}

/// Line buffer for parse-on-newline patterns where reads can split mid-line.
private final class LineCollector: @unchecked Sendable {
    private var pending = Data()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) {
        self.onLine = onLine
    }

    func append(_ chunk: Data) {
        pending.append(chunk)
        while let nl = pending.firstIndex(of: 0x0A) {
            let lineData = pending.subdata(in: pending.startIndex..<nl)
            pending.removeSubrange(pending.startIndex...nl)
            if let s = String(data: lineData, encoding: .utf8) {
                onLine(s)
            }
        }
    }
}
import Foundation
import Observation
import SwiftUI

/// Bidirectional bridge to an NCode subprocess running in SDK stream-json mode.
///
/// Spawns: `ncode --print --input-format stream-json --output-format stream-json
///          --session-id <uuid> --permission-mode bypassPermissions`
///
/// Writes user prompts as JSON to stdin. Reads assistant / tool_use /
/// result / system events from stdout. Each line of stdout is one JSON event,
/// parsed into `ChatEvent` values surfaced via @Observable.
@Observable
final class NCodeBridge {

    private(set) var isStarting = false
    private(set) var isRunning = false
    private(set) var lastError: String?
    private(set) var sessionId: String = UUID().uuidString
    private(set) var cwd: URL = HarnessClient.home

    private(set) var events: [ChatEvent] = []
    private(set) var statusBanner: String = ""

    /// Pending user messages we haven't received a `result` event for yet.
    /// Used to derive `isThinking`.
    private(set) var pendingTurnCount: Int = 0

    /// True when we've sent a user message but the matching `result` event
    /// hasn't arrived yet — i.e. the agent is working on a turn.
    var isThinking: Bool { pendingTurnCount > 0 && isRunning }

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private let ioQueue = DispatchQueue(label: "com.rasputinkaiser.harnessapp.ncode-bridge")

    init() {}

    // MARK: - Lifecycle

    @MainActor
    func start(cwd: URL? = nil) {
        if isRunning || isStarting { return }
        isStarting = true
        if let cwd { self.cwd = cwd }
        self.sessionId = UUID().uuidString
        statusBanner = "Starting NCode session…"

        let p = Process()
        let binPath = HarnessClient.home
            .appendingPathComponent(".local/bin/ncode", conformingTo: .text).path
        let resolvedBin = FileManager.default.isExecutableFile(atPath: binPath)
            ? binPath
            : "/usr/local/bin/ncode"
        guard FileManager.default.isExecutableFile(atPath: resolvedBin) else {
            lastError = "ncode binary not found at \(resolvedBin)"
            isStarting = false
            return
        }
        p.executableURL = URL(fileURLWithPath: resolvedBin)
        p.arguments = [
            "--print",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--session-id", sessionId,
            "--permission-mode", "bypassPermissions",
        ]
        p.currentDirectoryURL = self.cwd

        let outPipe = Pipe()
        let inPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = Pipe()
        p.standardInput = inPipe

        let buf = LineCollector { [weak self] line in
            self?.handleLine(line)
        }
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            buf.append(data)
        }

        do {
            try p.run()
            process = p
            stdinPipe = inPipe
            stdoutPipe = outPipe
            isRunning = true
            isStarting = false
            statusBanner = "Connected — send a message below"
            AppLogger.process.info("ncode bridge started (pid=\(p.processIdentifier))")

            // Critical: when ncode exits (after `result` event in --print mode
            // OR if killed externally), update internal state so the next send
            // doesn't try to write to a dead pipe.
            p.terminationHandler = { [weak self] proc in
                Task { @MainActor in
                    guard let self else { return }
                    self.isRunning = false
                    if self.isThinking {
                        self.pendingTurnCount = 0
                        // If killed mid-turn, surface a system note so the user
                        // knows the agent exited before responding.
                        self.events.append(.system(text: "ncode exited mid-turn (exit \(proc.terminationStatus))",
                                                    ts: Date(), uuid: UUID().uuidString))
                    }
                    self.statusBanner = "Session ended (exit \(proc.terminationStatus)). Start again to continue."
                    AppLogger.process.notice("ncode bridge ended (exit \(proc.terminationStatus))")
                }
            }
        } catch {
            lastError = "ncode launch failed: \(error.localizedDescription)"
            isStarting = false
        }
    }

    @MainActor
    func stop() {
        process?.terminate()
        pendingTurnCount = 0
        if let p = process {
            p.terminationHandler = { [weak self] proc in
                Task { @MainActor in
                    self?.isRunning = false
                    self?.statusBanner = "Session ended (exit \(proc.terminationStatus))"
                }
            }
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
    }

    @MainActor
    func clear() {
        events.removeAll()
        statusBanner = "Cleared"
    }

    // MARK: - Sending

    @MainActor
    func send(_ text: String) {
        guard let pipe = stdinPipe else {
            lastError = "not running"
            return
        }
        let payload: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": text],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var line = data
        line.append(0x0A)
        do {
            try pipe.fileHandleForWriting.write(contentsOf: line)
            events.append(.user(text: text, ts: Date(), uuid: UUID().uuidString))
            pendingTurnCount += 1
            statusBanner = ""
        } catch {
            lastError = "write failed: \(error.localizedDescription)"
        }
    }

    /// Interrupt the current turn. Sends SIGTERM to the running process —
    /// any partial output already buffered in `events` stays visible.
    @MainActor
    func interrupt() {
        guard isRunning else { return }
        process?.terminate()
        pendingTurnCount = 0
        statusBanner = "Interrupted"
        events.append(.system(text: "interrupted by user",
                               ts: Date(),
                               uuid: UUID().uuidString))
    }

    // MARK: - Receiving

    @MainActor
    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let type = (json["type"] as? String) ?? "?"
        let uuid = (json["uuid"] as? String) ?? UUID().uuidString
        let ts = parseTimestamp(json["timestamp"]) ?? Date()

        switch type {
        case "system":
            // Filter noise: hook_started/hook_response fire per-hook per-turn and
            // bury the signal. Keep only meaningful subtypes (errors, init summary).
            let subtype = (json["subtype"] as? String) ?? ""
            switch subtype {
            case "hook_started", "hook_response":
                return // silent — too chatty
            case "init":
                // init payload is ~5KB of tool/skill/plugin metadata that's
                // interesting as a status indicator but not as a transcript row.
                let model = (json["model"] as? String) ?? "?"
                let cwd = (json["cwd"] as? String) ?? "?"
                let mcpCount = ((json["mcp_servers"] as? [[String: Any]])?.count) ?? 0
                events.append(.system(text:
                    "session init — model=\(model), cwd=\(cwd), \(mcpCount) MCP servers connected",
                    ts: ts, uuid: uuid))
            default:
                events.append(.system(text: subtype, ts: ts, uuid: uuid))
            }
        case "assistant":
            // Parse to rich content list — text + tool_use blocks handled separately.
            let content = parseAssistantContent(json["message"] as? [String: Any])
            events.append(.assistant(content: content, ts: ts, uuid: uuid))
        case "user":
            // Server-echoed our message — skip
            break
        case "result":
            // Decrement pending turn counter — agent finished this turn.
            pendingTurnCount = max(0, pendingTurnCount - 1)
            // Pull useful metadata as a typed event.
            let subtype = (json["subtype"] as? String) ?? "result"
            let result = (json["result"] as? String) ?? ""
            let durationMs = (json["duration_ms"] as? Int) ?? 0
            let numTurns = (json["num_turns"] as? Int) ?? 1
            let isError = (json["is_error"] as? Bool) ?? false
            let usage = parseUsage(json["usage"] as? [String: Any])
            let cost = (json["total_cost_usd"] as? Double) ?? 0
            let stopReason = (json["stop_reason"] as? String) ?? "?"
            events.append(.result(text: result, subtype: subtype,
                                  durationMs: durationMs, numTurns: numTurns,
                                  isError: isError, usage: usage,
                                  cost: cost, stopReason: stopReason,
                                  ts: ts, uuid: uuid))
        case "rate_limit_event":
            // Informational, not core. Silent.
            return
        case "stream_event":
            return
        default:
            events.append(.other(type: type, raw: line, ts: ts, uuid: uuid))
        }
    }

    private func parseAssistantContent(_ msg: [String: Any]?) -> [AssistantBlock] {
        guard let msg = msg else { return [] }
        guard let arr = msg["content"] as? [[String: Any]] else {
            if let s = msg["content"] as? String {
                return [.text(s)]
            }
            return []
        }
        var out: [AssistantBlock] = []
        for block in arr {
            guard let t = block["type"] as? String else { continue }
            switch t {
            case "text":
                if let s = block["text"] as? String { out.append(.text(s)) }
            case "tool_use":
                let name = block["name"] as? String ?? "?"
                let id = block["id"] as? String ?? UUID().uuidString
                let input = block["input"] as? [String: Any] ?? [:]
                out.append(.toolUse(name: name, toolUseId: id,
                                    inputJSON: pretty(input)))
            case "tool_result":
                let id = block["tool_use_id"] as? String ?? "?"
                let content = (block["content"] as? String) ?? ""
                out.append(.toolResult(toolUseId: id,
                                       content: content))
            default:
                continue
            }
        }
        return out
    }

    private func parseUsage(_ u: [String: Any]?) -> TurnUsage? {
        guard let u = u else { return nil }
        return TurnUsage(
            inputTokens: (u["input_tokens"] as? Int) ?? 0,
            outputTokens: (u["output_tokens"] as? Int) ?? 0,
            cacheRead: (u["cache_read_input_tokens"] as? Int) ?? 0,
            cacheCreation: (u["cache_creation_input_tokens"] as? Int) ?? 0
        )
    }

    private func pretty(_ x: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: x, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "\(x)" }
        return s
    }

    private func parseTimestamp(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

/// Line buffer for parse-on-newline patterns where reads can split mid-line.
/// @unchecked Sendable because mutations are serialized via the consuming
/// DispatchQueue (the pipe's `readabilityHandler` runs on a serial queue).
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
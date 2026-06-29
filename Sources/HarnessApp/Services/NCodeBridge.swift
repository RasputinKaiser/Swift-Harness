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
        } catch {
            lastError = "ncode launch failed: \(error.localizedDescription)"
            isStarting = false
        }
    }

    @MainActor
    func stop() {
        process?.terminate()
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
            statusBanner = ""
        } catch {
            lastError = "write failed: \(error.localizedDescription)"
        }
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
            let msg = json["subtype"] as? String ?? "system"
            events.append(.system(text: msg, ts: ts, uuid: uuid))
        case "assistant":
            let text = extractAssistantText(json["message"] as? [String: Any])
            events.append(.assistant(text: text, ts: ts, uuid: uuid))
        case "user":
            // Echo from server (our sent message reflected back) — skip to avoid dup
            break
        case "result":
            let result = json["result"] as? String
            events.append(.result(text: result ?? "(empty)", ts: ts, uuid: uuid))
        case "stream_event":
            break
        default:
            events.append(.other(type: type, raw: line, ts: ts, uuid: uuid))
        }
    }

    private func parseTimestamp(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private func extractAssistantText(_ msg: [String: Any]?) -> String {
        guard let msg = msg else { return "" }
        let content = msg["content"]
        if let s = content as? String { return s }
        if let arr = content as? [[String: Any]] {
            let texts = arr.compactMap { block -> String? in
                let t = block["type"] as? String
                if t == "text", let s = block["text"] as? String { return s }
                if t == "tool_use" {
                    let name = block["name"] as? String ?? "?"
                    let input = block["input"] as? [String: Any] ?? [:]
                    let inputStr: String
                    if let p = input["file_path"] as? String {
                        inputStr = "(file: \(p))"
                    } else if let c = input["command"] as? String {
                        inputStr = "(cmd: \(c.prefix(80)))"
                    } else {
                        inputStr = input.isEmpty ? "" : "(\(input.count) keys)"
                    }
                    return "[tool_use: \(name) \(inputStr)]"
                }
                return nil
            }
            return texts.joined(separator: "\n")
        }
        return ""
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
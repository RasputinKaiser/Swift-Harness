import Foundation

/// Lightweight metadata for a known ncode session, read from ~/.ncode/sessions/<pid>.json.
struct SessionDescriptor: Identifiable, Hashable, Codable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let startedAtMs: Int
    let kind: String
    let entrypoint: String
    let name: String?

    var id: Int { pid }
    var startedAt: Date { Date(timeIntervalSince1970: TimeInterval(startedAtMs) / 1000.0) }
    var cwdURL: URL? { URL(fileURLWithPath: cwd) }
    var isInteractive: Bool { kind == "interactive" }

    private enum CodingKeys: String, CodingKey {
        case pid, sessionId, cwd, kind, entrypoint, name
        case startedAtMs = "startedAt"
    }

    /// Returns true if the PID is still alive (caller can kill(pid, 0)).
    var isAlive: Bool { kill(pid_t(pid), 0) == 0 }

    /// Encoded project path under ~/.ncode/projects/. Mirrors Claude Code's encoding.
    var encodedProjectPath: String {
        // Replace each '/' with '-' (leading '/' becomes leading '-'), matches -Users-ianzvirbulis- pattern.
        cwd.map { $0 == "/" ? "-" : String($0) }.joined()
    }

    /// File URL of the transcript JSONL.
    var transcriptURL: URL {
        HarnessClient.home
            .appendingPathComponent(".ncode/projects", conformingTo: .directory)
            .appendingPathComponent(encodedProjectPath, conformingTo: .directory)
            .appendingPathComponent("\(sessionId).jsonl", conformingTo: .text)
    }
}

/// Discrete events emitted from the transcript JSONL, parsed into typed rows
/// that the SessionsPane can render without re-parsing.
enum ActivityEvent: Identifiable, Hashable {
    case user(text: String, ts: Date, uuid: String)
    case assistant(text: String?, ts: Date, uuid: String)
    case system(text: String, ts: Date, uuid: String)
    case other(type: String, ts: Date, uuid: String)

    var id: String {
        switch self {
        case .user(_, _, let u): "user-\(u)"
        case .assistant(_, _, let u): "asst-\(u)"
        case .system(_, _, let u): "sys-\(u)"
        case .other(_, _, let u): "other-\(u)"
        }
    }

    var timestamp: Date {
        switch self {
        case .user(_, let t, _),
             .assistant(_, let t, _),
             .system(_, let t, _),
             .other(_, let t, _):
            t
        }
    }

    var iconName: String {
        switch self {
        case .user: "person.fill"
        case .assistant: "sparkles"
        case .system: "gearshape"
        case .other(let t, _, _):
            switch t {
            case "queue-operation": "arrow.triangle.branch"
            case "file-history-snapshot": "doc.on.doc"
            case "last-prompt": "pin"
            case "attachment": "paperclip"
            default: "circle"
            }
        }
    }

    var shortText: String {
        switch self {
        case .user(let s, _, _): s.prefix(120).description
        case .assistant(let s?, _, _): s.prefix(120).description
        case .assistant(nil, _, _): "(no text — tool call only)"
        case .system(let s, _, _): s.prefix(120).description
        case .other(let t, _, _): "[\(t)]"
        }
    }

    var tint: ActivityKind {
        switch self {
        case .user: .user
        case .assistant: .assistant
        case .system: .system
        case .other: .misc
        }
    }

    enum ActivityKind {
        case user, assistant, system, misc
    }
}

extension ActivityEvent {
    /// Parse one JSONL line into a typed event. Returns nil for malformed lines.
    static func parse(_ line: String) -> ActivityEvent? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let type = (json["type"] as? String) ?? "?"
        let uuid = (json["uuid"] as? String) ?? UUID().uuidString
        let ts = parseTimestamp(json["timestamp"]) ?? Date()

        switch type {
        case "user":
            let text = extractMessageContent(json)
            return .user(text: text, ts: ts, uuid: uuid)
        case "assistant":
            let text = extractMessageContent(json)
            return .assistant(text: text, ts: ts, uuid: uuid)
        case "system":
            let text = extractMessageContent(json)
            return .system(text: text, ts: ts, uuid: uuid)
        default:
            return .other(type: type, ts: ts, uuid: uuid)
        }
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        return f2.date(from: s)
    }

    /// Pulls plain text out of `message.content`, which can be either a String
    /// or an array of content blocks (text/tool_use/tool_result/...).
    private static func extractMessageContent(_ json: [String: Any]) -> String {
        guard let msg = json["message"] as? [String: Any] else { return "" }
        let content = msg["content"]
        if let s = content as? String { return s }
        if let arr = content as? [[String: Any]] {
            let texts = arr.compactMap { block -> String? in
                if let t = block["type"] as? String, t == "text",
                   let text = block["text"] as? String { return text }
                if let t = block["type"] as? String, t == "tool_use" {
                    let name = block["name"] as? String ?? "?"
                    return "[tool_use: \(name)]"
                }
                if let t = block["type"] as? String, t == "tool_result" {
                    if let c = block["content"] as? String { return "[tool_result: \(c.prefix(80))]" }
                    return "[tool_result]"
                }
                return nil
            }
            return texts.joined(separator: "\n")
        }
        return ""
    }
}
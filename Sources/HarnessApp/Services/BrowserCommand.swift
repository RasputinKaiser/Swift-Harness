import Foundation

/// Codable request the Python MCP server sends over the Unix socket.
struct BrowserCommand: Codable {
    let id: String          // correlation ID for matching reply
    let tool: String         // e.g. "browser_get_url", "browser_navigate"
    let args: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case id, tool, args
    }
}

/// Codable reply the app writes back.
struct BrowserReply: Codable {
    let id: String
    let ok: Bool
    let result: AnyCodable?
    let error: String?
}

/// Minimal AnyCodable for JSON values that aren't known at compile time.
/// Used for command args and reply results (heterogeneous JSON shapes).
enum AnyCodable: Codable, @unchecked Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyCodable])
    case object([String: AnyCodable])

    init?(_ value: Any?) {
        guard let value = value else { self = .null; return }
        if value is NSNull { self = .null; return }
        if let v = value as? Bool { self = .bool(v); return }
        if let v = value as? Int { self = .number(Double(v)); return }
        if let v = value as? Double { self = .number(v); return }
        if let v = value as? String { self = .string(v); return }
        if let v = value as? [Any] {
            self = .array(v.compactMap { AnyCodable($0) })
            return
        }
        if let v = value as? [String: Any] {
            var dict: [String: AnyCodable] = [:]
            for (k, val) in v {
                if let c = AnyCodable(val) { dict[k] = c }
            }
            self = .object(dict)
            return
        }
        return nil
    }

    var value: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .number(let v): return v
        case .string(let v): return v
        case .array(let v): return v.map { $0.value }
        case .object(let v): return v.mapValues { $0.value }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if try container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Double.self) {
            self = .number(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([AnyCodable].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: AnyCodable].self) {
            self = .object(v)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}
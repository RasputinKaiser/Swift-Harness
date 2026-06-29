import Foundation
import SwiftUI

/// One event in the NCode bridge chat stream.
enum ChatEvent: Identifiable, Hashable {
    case user(text: String, ts: Date, uuid: String)
    case assistant(text: String, ts: Date, uuid: String)
    case system(text: String, ts: Date, uuid: String)
    case result(text: String, ts: Date, uuid: String)
    case other(type: String, raw: String, ts: Date, uuid: String)

    var id: String {
        switch self {
        case .user(_, _, let u): "u-\(u)"
        case .assistant(_, _, let u): "a-\(u)"
        case .system(_, _, let u): "s-\(u)"
        case .result(_, _, let u): "r-\(u)"
        case .other(_, _, _, let u): "o-\(u)"
        }
    }

    var timestamp: Date {
        switch self {
        case .user(_, let t, _),
             .assistant(_, let t, _),
             .system(_, let t, _),
             .result(_, let t, _),
             .other(_, _, let t, _):
            t
        }
    }

    var iconName: String {
        switch self {
        case .user: "person.fill"
        case .assistant: "sparkles"
        case .system: "gearshape"
        case .result: "flag.checkered"
        case .other: "circle"
        }
    }

    var tint: Color {
        switch self {
        case .user: .blue
        case .assistant: .purple
        case .system: .gray
        case .result: .indigo
        case .other: .secondary
        }
    }

    var text: String {
        switch self {
        case .user(let s, _, _): s
        case .assistant(let s, _, _): s
        case .system(let s, _, _): s
        case .result(let s, _, _): s
        case .other(let t, let raw, _, _): "[\(t)] \(raw.prefix(120))"
        }
    }
}
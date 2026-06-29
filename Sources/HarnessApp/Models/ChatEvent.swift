import Foundation
import SwiftUI

/// One event in the NCode bridge chat stream.
enum ChatEvent: Identifiable, Hashable {

    case user(text: String, ts: Date, uuid: String)
    case assistant(content: [AssistantBlock], ts: Date, uuid: String)
    case system(text: String, ts: Date, uuid: String)
    case result(text: String, subtype: String, durationMs: Int, numTurns: Int,
                isError: Bool, usage: TurnUsage?, cost: Double, stopReason: String,
                ts: Date, uuid: String)
    case other(type: String, raw: String, ts: Date, uuid: String)

    var id: String {
        switch self {
        case .user(_, _, let u): "u-\(u)"
        case .assistant(_, _, let u): "a-\(u)"
        case .system(_, _, let u): "s-\(u)"
        case .result(_, _, _, _, _, _, _, _, _, let u): "r-\(u)"
        case .other(_, _, _, let u): "o-\(u)"
        }
    }

    var timestamp: Date {
        switch self {
        case .user(_, let t, _),
             .assistant(_, let t, _),
             .system(_, let t, _),
             .result(_, _, _, _, _, _, _, _, let t, _),
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
        case .user: return .blue
        case .assistant: return .purple
        case .system: return Color.gray
        case .result(let _, let subtype, _, _, let isError, _, _, _, _, _):
            if isError { return .red }
            return subtype == "success" ? .green : .indigo
        case .other: return Color.secondary
        }
    }

    var alignment: HorizontalAlignment {
        switch self {
        case .user: .trailing
        default: .leading
        }
    }
}

/// One block of an assistant message. Mirrors Anthropic content-block shape.
enum AssistantBlock: Hashable {
    case text(String)
    case toolUse(name: String, toolUseId: String, inputJSON: String)
    case toolResult(toolUseId: String, content: String)

    var iconName: String {
        switch self {
        case .text: "text.alignleft"
        case .toolUse: "wrench.and.screwdriver"
        case .toolResult: "checkmark.seal"
        }
    }

    var tint: Color {
        switch self {
        case .text: .purple
        case .toolUse: .orange
        case .toolResult: .green
        }
    }
}

/// Token usage for one turn, parsed from result event.
struct TurnUsage: Hashable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheRead: Int
    let cacheCreation: Int

    var totalTokens: Int { inputTokens + outputTokens }
}
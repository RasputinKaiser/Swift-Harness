import Foundation

/// Decoded entry from `~/.ncode/hook_events.jsonl`, written by the harness
/// extension `scripts/hook_event_tap.py`. Every wrapped hook fire lands one
/// JSON line here.
struct HookEvent: Identifiable, Hashable, Codable {
    let id: String
    let ts: String
    let event: String
    let script: String
    let toolName: String?
    let toolInputPreview: String?
    let exitCode: Int
    let durationMs: Int
    let outcome: Outcome
    let stdoutPreview: String
    let stderrPreview: String

    enum Outcome: String, Codable, Hashable, CaseIterable {
        case fire, skip, block, feedback, fail, timeout, error
        var label: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .fire: "checkmark.circle.fill"
            case .skip: "circle.dashed"
            case .block: "hand.raised.fill"
            case .feedback: "exclamationmark.bubble.fill"
            case .fail: "xmark.octagon.fill"
            case .timeout: "clock.badge.exclamationmark"
            case .error: "exclamationmark.triangle.fill"
            }
        }
        var tint: String {
            switch self {
            case .fire: "green"
            case .skip: "gray"
            case .block: "red"
            case .feedback: "orange"
            case .fail: "red"
            case .timeout: "orange"
            case .error: "red"
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, ts, event, script
        case toolName, toolInputPreview
        case exitCode, durationMs, outcome
        case stdoutPreview, stderrPreview
    }

    var date: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: ts) { return d }
        let f2 = ISO8601DateFormatter()
        return f2.date(from: ts)
    }

    var relativeTime: String {
        (date ?? Date()).formatted(.relative(presentation: .named))
    }
}
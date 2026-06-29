import SwiftUI

/// Shared pass/fail/warning color language for status badges across the app.
///
/// Codifies: green=pass, red=fail, orange=warning, blue=info, .secondary=pending.
/// Pulled out so panes (EvalPane, TestsPane, CostPane, JournalPane) use one
/// visual vocabulary instead of ad-hoc `.green` / `.red` choices per pane.
enum StatusTheme {
    static func color(for status: StatusKind) -> Color {
        switch status {
        case .pass: .green
        case .fail: .red
        case .warning: .orange
        case .info: .blue
        case .pending: .secondary
        case .neutral: .secondary
        }
    }

    static func icon(for status: StatusKind) -> String {
        switch status {
        case .pass: "checkmark.seal.fill"
        case .fail: "xmark.seal.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .pending: "circle.dotted"
        case .neutral: "circle"
        }
    }

    static func opacity(for status: StatusKind) -> Double {
        switch status {
        case .pending, .neutral: 0.08
        default: 0.15
        }
    }
}

enum StatusKind {
    case pass, fail, warning, info, pending, neutral
}

/// Capsule badge with a colored icon + label.
///
/// Use across panes to keep visual language consistent:
/// ```swift
/// StatusBadge(.pass, text: "12/15")
/// StatusBadge(.fail, text: "no", iconOnly: true)
/// ```
struct StatusBadge: View {
    let status: StatusKind
    let text: String
    let iconOnly: Bool

    init(_ status: StatusKind, text: String = "", iconOnly: Bool = false) {
        self.status = status
        self.text = text
        self.iconOnly = iconOnly
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: StatusTheme.icon(for: status))
                .font(.caption2.bold())
            if !iconOnly && !text.isEmpty {
                Text(text)
                    .font(.caption2.bold().monospacedDigit())
            }
        }
        .foregroundStyle(StatusTheme.color(for: status))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(
            StatusTheme.color(for: status).opacity(StatusTheme.opacity(for: status)),
            in: Capsule()
        )
    }
}
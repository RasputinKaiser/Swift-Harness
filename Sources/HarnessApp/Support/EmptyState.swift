import SwiftUI

/// Consistent empty-state component with optional call-to-action button.
///
/// Wraps ContentUnavailableView with two improvements:
/// 1. Optional CTA button (primary or bordered) at the bottom
/// 2. Optional secondary-info line under the description
///
/// Used across panes to make empty states more actionable — instead of just
/// "No X yet", the empty state can suggest what to do next ("Run X" button).
struct EmptyState: View {
    let title: String
    let systemImage: String
    let description: String?
    let actionTitle: String?
    let action: (() -> Void)?
    let secondaryInfo: String?

    init(_ title: String,
         systemImage: String,
         description: String? = nil,
         actionTitle: String? = nil,
         action: (() -> Void)? = nil,
         secondaryInfo: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
        self.secondaryInfo = secondaryInfo
    }

    var body: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: description.map { Text($0) }
            )
            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
            if let secondaryInfo = secondaryInfo {
                Text(secondaryInfo)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
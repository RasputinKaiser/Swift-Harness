import SwiftUI

/// Standardized pane header: icon + title + subtitle + Spacer + actions.
///
/// Use across panes to establish a consistent visual rhythm:
/// left-aligned (icon + titles), right-aligned (action buttons). Saves
/// every pane from re-inventing the same HStack layout.
///
/// ```swift
/// PaneHeader(
///     title: "Eval",
///     systemImage: "chart.bar.doc.horizontal",
///     subtitle: "\(cases.count) cases"
/// ) {
///     Button("Refresh", action: refresh)
///     Button("Run all", action: runAll).buttonStyle(.borderedProminent)
/// }
/// ```
struct PaneHeader<Actions: View>: View {
    let title: String
    let systemImage: String
    let subtitle: String?
    @ViewBuilder let actions: Actions

    init(_ title: String,
         systemImage: String,
         subtitle: String? = nil,
         @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.bold())
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            actions
        }
    }
}

import SwiftUI

/// Standard content wrapper for panes — establishes consistent padding,
/// scroll behavior, and readable max-width on wide displays.
///
/// Use across panes to keep visual rhythm consistent. Replaces the
/// ad-hoc `ScrollView { VStack {}.padding(24) }` pattern with a single
/// component that has:
/// - Consistent 24pt content padding (matches existing panes)
/// - Readable max-width (760pt) on wide displays; on narrow displays
///   content fills the available width
/// - Top-aligned content (matches existing panes)
/// - Optional header slot so panes don't reinvent the HStack layout
///
/// ```swift
/// PaneScaffold {
///     PaneHeader(title: "Status", systemImage: "speedometer") {
///         Button("Refresh", action: refresh)
///     }
///     metricsGrid
///     actionsCard
/// }
/// ```
struct PaneScaffold<Content: View>: View {
    let alignment: HorizontalAlignment
    let spacing: CGFloat
    let padding: CGFloat
    let readableMaxWidth: CGFloat?
    @ViewBuilder let content: Content

    init(alignment: HorizontalAlignment = .leading,
         spacing: CGFloat = 16,
         padding: CGFloat = 24,
         readableMaxWidth: CGFloat? = 760,
         @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.padding = padding
        self.readableMaxWidth = readableMaxWidth
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: alignment, spacing: spacing) {
                content
            }
            .padding(padding)
            .frame(maxWidth: readableMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Tight padding variant for panes that show dense grids/lists and benefit
/// from more horizontal real estate (Status, Telemetry).
struct DensePaneScaffold<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        PaneScaffold(spacing: 12, padding: 20, readableMaxWidth: 920) {
            content
        }
    }
}

/// Full-width variant for panes that should NOT constrain to a readable
/// max-width (Tests, Journal, Manifest — they show wide tables/code).
struct FullWidthPaneScaffold<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        PaneScaffold(readableMaxWidth: nil) {
            content
        }
    }
}
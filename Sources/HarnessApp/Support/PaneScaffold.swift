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

/// Concentric border-radius scale.
///
/// `outer = inner + padding` — nested rounded surfaces need their outer
/// radius to exceed the inner by roughly the inner padding. Picking from
/// one scale keeps card shapes in a single visual family across the app.
enum DesignRadius {
    static let small: CGFloat = 6     // badges, code chips, mini buttons
    static let medium: CGFloat = 10    // cards in a grid, code blocks
    static let large: CGFloat = 14    // section containers, sheets, modals
}

/// Tactile press feedback. Scales to 0.96 while pressed, spring returns.
///
/// Use on primary / bordered-prominent buttons where tactile feel matters.
/// For borderless icon buttons in tight toolbars, prefer `.buttonStyle(.borderless)`
/// to keep hit areas tight.
struct TactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7),
                       value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Standard card surface — `.regularMaterial` + 0.5pt hairline border +
/// a soft shadow instead of relying on a hard `Divider` for separation.
///
/// Layer with concentric radius in mind: a card that hosts another rounded
/// element should use `DesignRadius.large` while the inner uses `medium` or
/// `small`, so `outer inner + padding`.
extension View {
    func materialCard(radius: CGFloat = DesignRadius.large,
                      padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.black.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

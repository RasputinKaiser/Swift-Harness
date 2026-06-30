import SwiftUI

/// Shared metric card for dashboard grids (Status, Cost, Telemetry panes).
///
/// Uses `materialCard()` for consistent radius, shadow, and hairline border
/// across all panes that show summary numbers.
struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(.title, design: .rounded).bold())
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .materialCard(radius: DesignRadius.large, padding: 14)
    }
}

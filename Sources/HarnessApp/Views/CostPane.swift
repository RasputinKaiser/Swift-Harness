import SwiftUI

/// Cost tracker pane — surfaces per-session cost data from the NCode bridge.
/// Shows accumulated cost, token counts, and per-turn breakdown.
/// Includes a budget warning when cost exceeds a user-set threshold.
struct CostPane: View {
    @Environment(HarnessStore.self) private var store
    @State private var budgetThreshold: Double = 10.0
    @State private var thresholdEnabled = false

    var body: some View {
        DensePaneScaffold {
            summaryCards
            budgetSection
            perTurnBreakdown
        }
        .navigationTitle("Cost")
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        // Use cached incremental totals from NCodeBridge — avoids O(n) re-scan
        // of the events array on every CostPane render.
        let totalCost = store.bridge.totalCost
        let totalInput = store.bridge.totalInputTokens
        let totalOutput = store.bridge.totalOutputTokens
        // Average duration from cached result events (much smaller than full
        // events array — only result events, not user/assistant/system).
        let durations = store.bridge.resultEvents.map { $0.duration }
        let avgDuration = durations.isEmpty ? 0 : durations.reduce(0, +) / durations.count

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            MetricCard(title: "Total Cost",
                        value: String(format: "$%.4f", totalCost),
                        systemImage: "dollarsign.circle.fill",
                        tint: totalCost > budgetThreshold && thresholdEnabled ? .red : .green)
            MetricCard(title: "Input Tokens",
                        value: formatNum(totalInput),
                        systemImage: "arrow.down.circle.fill",
                        tint: .blue)
            MetricCard(title: "Output Tokens",
                        value: formatNum(totalOutput),
                        systemImage: "arrow.up.circle.fill",
                        tint: .purple)
            MetricCard(title: "Turns",
                        value: "\(store.bridge.resultEvents.count)",
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: .orange)
            MetricCard(title: "Avg Duration",
                        value: "\(avgDuration)ms",
                        systemImage: "clock.fill",
                        tint: .secondary)
        }
    }

    // MARK: - Budget section

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Budget")
                .font(.headline)
            HStack {
                Toggle("Enable budget warning", isOn: $thresholdEnabled)
                Spacer()
                if thresholdEnabled {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("Threshold", value: $budgetThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
            }
            if thresholdEnabled {
                let total = totalCost
                let pct = budgetThreshold > 0 ? min(total / budgetThreshold * 100, 100) : 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(format: "$%.4f", total))
                            .font(.system(.body, design: .monospaced).bold())
                        Text("/ $\(String(format: "%.2f", budgetThreshold))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", pct))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(pct >= 100 ? .red : pct >= 80 ? .orange : .green)
                    }
                    ProgressView(value: min(total, budgetThreshold), total: budgetThreshold)
                        .tint(pct >= 100 ? .red : pct >= 80 ? .orange : .green)
                    if pct >= 100 {
                        Label("Budget exceeded!", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                    } else if pct >= 80 {
                        Label("Approaching budget limit", systemImage: "warning")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Per-turn breakdown

    @ViewBuilder
    private var perTurnBreakdown: some View {
        let results = store.bridge.resultEvents
        if results.isEmpty {
            Text("No turns completed yet — start a chat to see per-turn cost data.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Per-Turn Breakdown")
                    .font(.headline)
                ForEach(results, id: \.turn) { r in
                    HStack(spacing: 12) {
                        Text("Turn \(r.turn)")
                            .font(.caption2.bold().monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Text(String(format: "$%.4f", r.cost))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.green)
                            .frame(width: 70, alignment: .leading)
                        Text(formatNum(r.input))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.blue)
                            .frame(width: 60, alignment: .leading)
                        Text(formatNum(r.output))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.purple)
                            .frame(width: 60, alignment: .leading)
                        Text("\(r.duration)ms")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(r.stop)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    private var totalCost: Double {
        store.bridge.totalCost
    }

    private func formatNum(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

private struct MetricCard: View {
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
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
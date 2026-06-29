import SwiftUI

/// Evaluation harness pane — lists benchmark cases and runs them against the
/// live NCode model config to measure agent quality.
///
/// Visual design (Tier 5 polish):
/// - Each case is a card with a colored status icon, tier/difficulty pills,
///   and a proportional score bar showing pass fraction.
/// - Expandable checks list with per-check pass/fail indicators.
/// - Run-all and per-case Run buttons; run-in-progress shimmer.
/// - Header with case count + sandbox path + total pass rate summary.
struct EvalPane: View {
    @Environment(HarnessStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                caseList
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Eval")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: refresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear { refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Evaluation Harness")
                        .font(.title3.bold())
                    Text("\(store.evalCases.cases.count) cases")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                totalPassRateBadge
                Button(action: runAll) {
                    Label("Run all", systemImage: "play.circle.fill")
                        .padding(.horizontal, 10).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(store.eval.isRunning || store.evalCases.cases.isEmpty)
                if store.eval.isRunning {
                    ProgressView().controlSize(.small)
                }
            }
            Text(store.evalCases.casesDir.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var totalPassRateBadge: some View {
        let stats = passStats
        if stats.total > 0 {
            let rate = Double(stats.passed) / Double(stats.total)
            let color: Color = rate >= 0.8 ? .green : (rate >= 0.5 ? .orange : .red)
            HStack(spacing: 4) {
                Text(String(format: "%.0f%%", rate * 100))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(color)
                Text("(\(stats.passed)/\(stats.total))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.1), in: Capsule())
        }
    }

    private var passStats: (passed: Int, total: Int) {
        var passed = 0
        var total = 0
        for c in store.evalCases.cases {
            if let last = store.evalCases.lastRun(for: c.id) {
                total += 1
                if last.passed ?? false { passed += 1 }
            }
        }
        return (passed, total)
    }

    private var caseList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.evalCases.cases.isEmpty {
                ContentUnavailableView(
                    "No eval cases found",
                    systemImage: "questionmark.folder",
                    description: Text("Refresh should seed defaults at\n\(store.evalCases.casesDir.path)")
                )
                .frame(maxWidth: .infinity)
            } else {
                ForEach(store.evalCases.cases) { c in
                    EvalCaseCard(case_: c)
                }
            }
        }
    }

    private func refresh() {
        Task { @MainActor in store.evalCases.refresh() }
    }

    private func runAll() {
        Task {
            for c in store.evalCases.cases {
                _ = await store.eval.run(case: c)
            }
            await MainActor.run { store.evalCases.refresh() }
        }
    }
}

/// Single case card — status icon, badges, prompt preview, score bar, runs list.
private struct EvalCaseCard: View {
    let case_: EvalCase
    @Environment(HarnessStore.self) private var store
    @State private var expanded = false
    @State private var pendingRun = false

    var body: some View {
        let last = store.evalCases.lastRun(for: case_.id)
        VStack(alignment: .leading, spacing: 8) {
            headerRow(last: last)
            scoreBar(last: last)
            promptPreview
            if expanded {
                Divider()
                checksList(last: last)
                tagsRow
                if let last = last {
                    runMetadataRow(last: last)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            statusColor(last: last).opacity(expanded ? 0.5 : 0.2),
                            lineWidth: expanded ? 1.5 : 1
                        )
                )
        )
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }
    }

    private func headerRow(last: EvalRun?) -> some View {
        HStack(spacing: 8) {
            statusIcon(last: last)
            tierBadge
            difficultyBadge
            Text(case_.id)
                .font(.system(.callout, design: .monospaced).bold())
            Spacer()
            if pendingRun && store.eval.isRunning {
                ProgressView().controlSize(.small)
            }
            Button(action: runOne) {
                Image(systemName: "play.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(store.eval.isRunning ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
            }
            .buttonStyle(.borderless)
            .help("Run this case")
            .disabled(store.eval.isRunning || pendingRun)
        }
    }

    @ViewBuilder
    private func statusIcon(last: EvalRun?) -> some View {
        Image(systemName: statusIconName(last: last))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(statusColor(last: last))
    }

    private func statusIconName(last: EvalRun?) -> String {
        if pendingRun && store.eval.isRunning { return "circle.dotted" }
        if let last = last {
            if last.errorMessage != nil { return "exclamationmark.triangle.fill" }
            return (last.passed ?? false) ? "checkmark.seal.fill" : "xmark.seal.fill"
        }
        return "circle.dashed"
    }

    private func statusColor(last: EvalRun?) -> Color {
        if pendingRun && store.eval.isRunning { return .secondary }
        if let last = last {
            if last.errorMessage != nil { return .orange }
            return (last.passed ?? false) ? .green : .red
        }
        return .secondary
    }

    @ViewBuilder
    private func scoreBar(last: EvalRun?) -> some View {
        if let last = last, let score = last.score {
            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary.opacity(0.3))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor(score: score))
                            .frame(width: max(2, geo.size.width * score), height: 6)
                    }
                }
                .frame(height: 6)
                Text(String(format: "%.0f%%", score * 100))
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(barColor(score: score))
                    .frame(width: 36, alignment: .trailing)
            }
            .frame(maxWidth: 220)
        } else {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary.opacity(0.2))
                    .frame(height: 4)
                Text("not run")
                    .font(.caption2.italic())
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 220)
        }
    }

    private func barColor(score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.5 { return .orange }
        return .red
    }

    private var promptPreview: some View {
        Text(case_.prompt.prefix(140).description)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(expanded ? nil : 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tierBadge: some View {
        let color: Color = case_.tier == .process ? .blue : .purple
        return Text(case_.tier.rawValue.uppercased())
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var difficultyBadge: some View {
        let color: Color = case_.difficulty == .trivial ? .green :
            case_.difficulty == .moderate ? .orange : .red
        return Text(case_.difficulty.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func checksList(last: EvalRun?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Grading checks (\(case_.grading.count))")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(Array(case_.grading.enumerated()), id: \.offset) { i, check in
                HStack(spacing: 6) {
                    let result = last?.checkResults.indices.contains(i) == true
                        ? last?.checkResults[i] : nil
                    if let r = result {
                        Image(systemName: r.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(r.passed ? .green : .red)
                            .font(.caption2)
                    } else {
                        Image(systemName: "circle")
                            .foregroundStyle(.tertiary)
                            .font(.caption2)
                    }
                    Text("\(i + 1).")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Text(check.kind.rawValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                    if let result = result, !result.evidence.isEmpty {
                        Text("— \(result.evidence)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text(argumentsPreview(check.arguments))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer()
                    Text(String(format: "w%.1f", check.weight))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func runMetadataRow(last: EvalRun) -> some View {
        HStack(spacing: 12) {
            if let ts = last.finishedAt {
                Label(ts.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "clock")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Label("\(last.toolCount)", systemImage: "wrench.and.screwdriver")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            if let err = last.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var tagsRow: some View {
        HStack(spacing: 4) {
            ForEach(case_.tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.tint.opacity(0.08), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("threshold \(String(format: "%.0f%%", case_.passThreshold * 100))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    private func argumentsPreview(_ args: [String: String]) -> String {
        let pairs = args.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }
        return pairs.joined(separator: " ")
    }

    private func runOne() {
        pendingRun = true
        Task {
            _ = await store.eval.run(case: case_)
            await MainActor.run {
                pendingRun = false
                store.evalCases.refresh()
            }
        }
    }
}
import SwiftUI

/// Evaluation harness pane — lists benchmark cases and runs them against the
/// live NCode model config to measure agent quality.
///
/// Phase 1: case discovery + deterministic graders + seed cases.
/// Phase 2 (this version): EvalRunner spawns ncode per case in a sandbox cwd,
/// captures the tool_use sequence, grades via EvalGrader, records to
/// ~/.ncode/eval/results.jsonl, and surfaces last score per case.
struct EvalPane: View {
    @Environment(HarnessStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
        VStack(alignment: .leading, spacing: 4) {
            Label("Evaluation Harness", systemImage: "chart.bar.doc.horizontal")
                .font(.title3.bold())
            Text("\(store.evalCases.cases.count) cases at \(store.evalCases.casesDir.path)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                Button(action: runAll) {
                    Label("Run all", systemImage: "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(store.eval.isRunning || store.evalCases.cases.isEmpty)
                if store.eval.isRunning {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.top, 4)
        }
    }

    private var caseList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.evalCases.cases.isEmpty {
                ContentUnavailableView(
                    "No eval cases found",
                    systemImage: "questionmark.folder",
                    description: Text("Tapping Refresh should seed defaults at \(store.evalCases.casesDir.path)")
                )
            } else {
                ForEach(store.evalCases.cases) { c in
                    EvalCaseRow(case_: c)
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

private struct EvalCaseRow: View {
    let case_: EvalCase
    @Environment(HarnessStore.self) private var store
    @State private var expanded = false
    @State private var pendingRun = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                tierBadge
                difficultyBadge
                Text(case_.id)
                    .font(.system(.callout, design: .monospaced).bold())
                Spacer()
                lastScoreBadge
                Button(action: runOne) {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .help("Run this case")
                .disabled(store.eval.isRunning || pendingRun)
            }
            Text(case_.prompt.prefix(140).description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 2)
            if expanded {
                checksList
                tagsRow
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .onTapGesture { expanded.toggle() }
    }

    @ViewBuilder
    private var lastScoreBadge: some View {
        if let last = store.evalCases.lastRun(for: case_.id) {
            let passed = last.passed ?? false
            let scoreText = String(format: "%.0f%%", (last.score ?? 0) * 100)
            let color: Color = passed ? .green : .red
            if pendingRun && store.eval.isRunning {
                ProgressView().controlSize(.small)
            } else {
                Label(scoreText, systemImage: passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(color)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(color.opacity(0.1), in: Capsule())
            }
        } else if pendingRun {
            ProgressView().controlSize(.small)
        } else {
            Text("not run")
                .font(.caption2.italic())
                .foregroundStyle(.tertiary)
        }
    }

    private var tierBadge: some View {
        let color: Color = case_.tier == .process ? .blue : .purple
        return Text(case_.tier.rawValue)
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

    private var checksList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Checks:")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            ForEach(Array(case_.grading.enumerated()), id: \.offset) { i, check in
                HStack(spacing: 6) {
                    Text("\(i + 1).")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Text(check.kind.rawValue)
                        .font(.system(.caption, design: .monospaced))
                    Text(argumentsPreview(check.arguments))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(String(format: "w%.1f", check.weight))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.top, 4)
    }

    private var tagsRow: some View {
        HStack(spacing: 4) {
            ForEach(case_.tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.tint.opacity(0.1), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("threshold \(String(format: "%.0f%%", case_.passThreshold * 100))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
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
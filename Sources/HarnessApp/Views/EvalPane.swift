import SwiftUI

/// Evaluation harness pane — lists benchmark cases and (Phase 2) runs them
/// against the live NCode model config to measure quality.
///
/// Phase 1 ships: case discovery, seed cases, view of case metadata + checks.
/// Phase 2 will add: EvalRunner that invokes NCodeBridge per case, transcript
/// grading, results JSONL, and pass/fail visualization over time.
struct EvalPane: View {
    @Environment(HarnessStore.self) private var store
    @State private var evalStore = EvalCaseStore()
    @State private var selectedCaseId: String?

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
            Text("\(evalStore.cases.count) cases at \(evalStore.casesDir.path)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("Phase 1 — case discovery + deterministic graders. Runner + results JSONL ship in Phase 2.")
                .font(.caption2.italic())
                .foregroundStyle(.tertiary)
        }
    }

    private var caseList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if evalStore.cases.isEmpty {
                ContentUnavailableView(
                    "No eval cases found",
                    systemImage: "questionmark.folder",
                    description: Text("Tapping Refresh should seed defaults at \(evalStore.casesDir.path)")
                )
            } else {
                ForEach(evalStore.cases) { c in
                    EvalCaseRow(case_: c, isSelected: selectedCaseId == c.id)
                        .onTapGesture { selectedCaseId = (selectedCaseId == c.id) ? nil : c.id }
                }
            }
        }
    }

    private func refresh() {
        Task { @MainActor in evalStore.refresh() }
    }
}

private struct EvalCaseRow: View {
    let case_: EvalCase
    let isSelected: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                tierBadge
                difficultyBadge
                Text(case_.id)
                    .font(.system(.callout, design: .monospaced).bold())
                Spacer()
                Text("\(case_.grading.count) checks")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(case_.prompt.prefix(140).description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(isSelected ? nil : 2)
            if isSelected {
                checksList
                tagsRow
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.tint.opacity(isSelected ? 0.5 : 0), lineWidth: 1)
        )
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
}
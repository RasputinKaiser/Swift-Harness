import SwiftUI

struct StatusPane: View {
    @Environment(HarnessStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                metricsGrid
                if let entry = store.latestImprovement {
                    latestImprovementCard(entry)
                }
                actions
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Status")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.refreshStatus() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Harness Status")
                .font(.largeTitle).bold()
            if let ts = store.latestImprovementAt {
                Text("Last update \(ts.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No improvement journal yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            MetricCard(
                title: "Memory Fabric Records",
                value: "\(store.memoryRecordCount)",
                systemImage: "brain.head.profile",
                tint: .blue
            )
            MetricCard(
                title: "Snapshots",
                value: "\(store.snapshotCount)",
                systemImage: "archivebox",
                tint: .purple
            )
            MetricCard(
                title: "Continuity Packs",
                value: "\(store.continuityCount)",
                systemImage: "arrow.triangle.branch",
                tint: .indigo
            )
            if let s = store.testSummary {
                MetricCard(
                    title: "Tests",
                    value: "\(s.passed)/\(s.total)",
                    systemImage: s.allGreen ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                    tint: s.allGreen ? .green : .orange
                )
            } else {
                MetricCard(
                    title: "Tests",
                    value: "--",
                    systemImage: "checkmark.seal",
                    tint: .secondary
                )
            }
        }
    }

    private func latestImprovementCard(_ entry: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Latest self-correction entry", systemImage: "doc.text")
                .font(.headline)
            ScrollView {
                Text(entry)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                Task { await store.runTests() }
            } label: {
                Label("Run Tests", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)

            Button {
                Task { await store.sweep() }
            } label: {
                Label("Sweep (/improve)", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)

            Button {
                Task { await store.snapshot(reason: "via harness-app status pane") }
            } label: {
                Label("Snapshot", systemImage: "camera")
            }
            .buttonStyle(.bordered)

            if store.isRunningTests {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
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
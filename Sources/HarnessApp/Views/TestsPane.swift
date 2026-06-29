import SwiftUI

struct TestsPane: View {
    @Environment(HarnessStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            outputView
            if let r = store.testResult {
                Divider()
                statusBar(r)
            }
        }
        .navigationTitle("Tests")
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await store.runTests() }
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isRunningTests)

            Button {
                Task { await store.refreshStatus() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(store.isRunningTests)

            if store.isRunningTests {
                ProgressView("Running tests…")
                    .controlSize(.small)
                    .padding(.leading, 6)
            }
            Spacer()

            if let s = store.testSummary {
                Label("\(s.passed) pass", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(.callout, design: .monospaced))
                Label("\(s.failed) fail", systemImage: s.failed == 0 ? "circle" : "exclamationmark.triangle.fill")
                    .foregroundStyle(s.failed == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                    .font(.system(.callout, design: .monospaced))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var outputView: some View {
        if let r = store.testResult {
            ScrollView {
                Text(r.stdout.isEmpty ? r.stderr : r.stdout)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        } else {
            ContentUnavailableView(
                "No test run yet",
                systemImage: "checkmark.seal",
                description: Text("Click Run to execute ~/.ncode/scripts/run_tests.py")
            )
        }
    }

    private func statusBar(_ r: HarnessClient.RunResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(r.ok ? .green : .red)
            Text(r.ok ? "PASSED" : "FAILED")
                .font(.system(.headline, design: .monospaced))
            Spacer()
            Text(String(format: "%.1fs", r.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("exit \(r.exitCode)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }
}
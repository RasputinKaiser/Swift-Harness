import Foundation
import SwiftUI

@Observable
final class HarnessStore {

    // MARK: - Paths

    var ncodeDir: URL { HarnessClient.ncodeDir }
    var scriptsDir: URL { HarnessClient.scriptsDir }

    // MARK: - Mutable state

    var isRunningTests = false
    var testResult: HarnessClient.RunResult?
    var testSummary: TestSummary?

    var memoryRecordCount = 0
    var recentRecords: [MemoryFabricClient.Record] = []

    var latestImprovement: String?
    var latestImprovementAt: Date?
    var snapshotCount: Int = 0
    var continuityCount: Int = 0

    var statusMessage: String = ""

    /// Live session tailer. Used by SessionsPane.
    var liveSession = SessionActivityStore()

    /// Snapshot catalog. Used by SnapshotsPane.
    var snapshotStore = SnapshotStore()

    /// Hook-event tailer. Backs HooksPane.
    var hookEvents = HookEventStore()

    /// Plugin drift detector. Backs PluginPane.
    var pluginMirror = PluginMirrorStore()

    /// Memory Fabric explorer. Backs Memory pane.
    var memory = MemoryStore()

    /// Bidirectional NCode subprocess for the Chat pane.
    var bridge = NCodeBridge()

    /// Project navigator. Backs the Projects sidebar section.
    var projects = ProjectStore()

    // MARK: - Init

    init() {
        Task { await refreshStatus() }
    }

    // MARK: - Actions

    func runTests() async {
        guard !isRunningTests else { return }
        isRunningTests = true
        defer { isRunningTests = false }
        statusMessage = "Running run_tests.py…"
        let script = HarnessClient.scriptPath("run_tests.py")
        let r = await HarnessClient.run(
            command: ["/usr/bin/env", "python3", script.path],
            cwd: ncodeDir
        )
        testResult = r
        testSummary = HarnessClient.parseTestCountFromStdout(r.stdout).map(TestSummary.init)
        statusMessage = r.ok ? "Tests complete (exit 0)" : "Tests failed (exit \(r.exitCode))"
        await refreshStatus()
    }

    func sweep() async {
        statusMessage = "Running self_correct.py…"
        let script = HarnessClient.scriptPath("self_correct.py")
        let _ = await HarnessClient.run(
            command: ["/usr/bin/env", "python3", script.path],
            cwd: ncodeDir
        )
        statusMessage = "Self-correction sweep complete"
        await refreshStatus()
    }

    func snapshot(reason: String) async {
        statusMessage = "Snapshotting harness…"
        let script = HarnessClient.scriptPath("snapshot_harness.py")
        let r = await HarnessClient.run(
            command: ["/usr/bin/env", "python3", script.path, "--reason", reason],
            cwd: ncodeDir
        )
        statusMessage = r.ok ? "Snapshot saved" : "Snapshot failed: \(r.stderr.prefix(120))"
        await refreshStatus()
    }

    func refreshStatus() async {
        latestImprovement = HarnessClient.latestImprovementEntry()
        latestImprovementAt = HarnessClient.latestImprovementTimestamp()
        snapshotCount = HarnessClient.snapshotCount()
        continuityCount = HarnessClient.continuityCount()
        // Memory count is fetched lazily by MemoryPane via MemoryStore.bootstrap();
        // we don't duplicate the call here — Status pane can show count from
        // store.memory.totalCount if it's been queried.
        statusMessage = "Status refreshed"
    }

    struct TestSummary: Equatable {
        let passed: Int
        let failed: Int
        var allGreen: Bool { failed == 0 }
        var total: Int { passed + failed }
    }
}
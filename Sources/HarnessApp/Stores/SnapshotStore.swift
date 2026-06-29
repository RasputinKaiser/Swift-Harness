import Foundation
import Observation

/// `@Observable` snapshot catalog. Refreshes on demand (CLI tasks are fast — no
/// need for DispatchSource polling on a dir that mutates only at human cadence).
@Observable
final class SnapshotStore {

    private(set) var snapshots: [Snapshot] = []
    private(set) var diffsByHash: [String: [SnapshotFileDiff]] = [:]
    private(set) var lastRefresh: Date?
    private(set) var isExportingSnapshot = false  ///< currently taking a snapshot
    private(set) var isRestoring = false
    private(set) var lastError: String?

    init() {}

    /// Refresh from disk. Safe to call from any actor; mutations are quick.
    @MainActor
    func refresh() {
        snapshots = HarnessClient.listSnapshots()
        diffsByHash.removeAll()
        for snap in snapshots {
            diffsByHash[snap.hash] = HarnessClient.diffSnapshot(snap)
        }
        lastRefresh = Date()
        lastError = nil
    }

    /// Convenience: count of drifted files for a given snapshot.
    func driftedCount(_ snapshot: Snapshot) -> Int {
        (diffsByHash[snapshot.hash] ?? []).filter { $0.drifted }.count
    }

    /// Take a new snapshot via the harness script. Captures stderr/stdout via
    /// the simple block-call path — Phase 5 streamer takes over in Phase 2.x.
    @MainActor
    func takeSnapshot(reason: String) async {
        isExportingSnapshot = true
        defer { isExportingSnapshot = false }
        lastError = nil
        let r = await HarnessClient.run(
            command: ["python3", HarnessClient.scriptPath("snapshot_harness.py").path,
                     "--reason", reason],
            cwd: HarnessClient.ncodeDir
        )
        if !r.ok {
            lastError = "snapshot_harness.py failed: \(r.stderr.prefix(200))"
            return
        }
        refresh()
    }

    /// Restore a snapshot. Auto-snapshots the live state first via the
    /// harness script's pre-restore backup — the script handles safety.
    @MainActor
    func restore(hash: String) async {
        isRestoring = true
        defer { isRestoring = false }
        lastError = nil
        let r = await HarnessClient.run(
            command: ["python3", HarnessClient.scriptPath("restore_harness.py").path, hash],
            cwd: HarnessClient.ncodeDir
        )
        if !r.ok {
            lastError = "restore_harness.py failed: \(r.stderr.prefix(240))"
            return
        }
        refresh()
    }
}
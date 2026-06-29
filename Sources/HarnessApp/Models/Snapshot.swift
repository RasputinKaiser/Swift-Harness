import Foundation

/// Value struct decoded from `~/.ncode/backups/snapshots/<hash>/manifest.json`.
struct Snapshot: Identifiable, Hashable, Codable {
    let hash: String
    let createdAt: String  // ISO8601 with offset
    let reason: String
    let files: [File]

    var id: String { hash }

    struct File: Hashable, Codable {
        let name: String
        let sha256: String
    }

    /// Parsed created date — best-effort; raw ISO string is also kept for display.
    var createdAtDate: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: createdAt) { return d }
        let f2 = ISO8601DateFormatter()
        return f2.date(from: createdAt)
    }

    /// `Snapshots/` directory URL — resolved lazily because the manifest
    /// itself doesn't include the path.
    var directoryURL: URL {
        HarnessClient.snapshotsDir.appendingPathComponent(hash, conformingTo: .directory)
    }
}

/// Comparison result for one file across the snapshot + live tree.
struct SnapshotFileDiff: Identifiable, Hashable {
    let name: String
    let snapshotHash: String
    let liveHash: String?
    var drifted: Bool { liveHash != snapshotHash }
    var liveMissing: Bool { liveHash == nil }
    var id: String { name }
}
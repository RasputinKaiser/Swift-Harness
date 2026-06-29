import Foundation
import CryptoKit

extension HarnessClient {

    /// All snapshots on disk, newest-first by manifest mtime.
    static func listSnapshots() -> [Snapshot] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: snapshotsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return []
        }
        var out: [(Snapshot, Date)] = []
        for dir in entries where dir.hasDirectoryPath {
            let manifest = dir.appendingPathComponent("manifest.json", conformingTo: .text)
            guard let data = try? Data(contentsOf: manifest),
                  let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { continue }
            let mtime = (try? manifest.resourceValues(forKeys: [.contentModificationDateKey])
                            .contentModificationDate) ?? Date.distantPast
            out.append((snap, mtime))
        }
        return out.sorted(by: { $0.1 > $1.1 }).map { $0.0 }
    }

    /// SHA-256 of the current live script at ~/.ncode/scripts/<name>. Empty if missing.
    static func sha256OfLiveScript(_ name: String) -> String? {
        let path = scriptsDir.appendingPathComponent(name, conformingTo: .text)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Per-file drift between a snapshot and the current live tree.
    static func diffSnapshot(_ snapshot: Snapshot) -> [SnapshotFileDiff] {
        snapshot.files.map { file in
            SnapshotFileDiff(
                name: file.name,
                snapshotHash: file.sha256,
                liveHash: sha256OfLiveScript(file.name)
            )
        }
    }
}
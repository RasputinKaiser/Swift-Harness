import Foundation
import CryptoKit
import Observation

/// `@Observable` drift detector between source repo, last installed manifest,
/// and the live install cache.
///
/// Reads:
/// - `~/.ncode/.harness.installed.json` (manifest written by install.sh)
/// - `~/Code/harness-self-improvement/scripts/*.py` (source repo)
/// - `~/.ncode/plugins/marketplaces/harness-local/scripts/*.py` (live cache)
///
/// Surfaces drift via `snapshot: PluginDriftSnapshot?`. Null = no manifest yet
/// (install.sh has never been run on the live tree).
@Observable
final class PluginMirrorStore {

    private(set) var manifest: PluginInstallManifest?
    private(set) var drift: PluginDriftSnapshot?
    private(set) var lastRefresh: Date?
    private(set) var isInstalling = false
    private(set) var lastInstallError: String?
    private(set) var sourceCommitShort: String = "?"

    /// Pure check status: "in-sync" / "drift detected" / "no manifest"
    var statusLabel: String {
        if manifest == nil { return "no manifest — install.sh not yet run" }
        guard let d = drift else { return "checking…" }
        if d.changedCount == 0 {
            return "in-sync at \(sourceCommitShort)"
        }
        return "drift — \(d.changedCount) files changed"
    }

    init() {}

    @MainActor
    func refresh() {
        manifest = readManifest()
        if manifest == nil {
            drift = nil
            lastRefresh = Date()
            return
        }
        let workingFiles = collectDrift()
        let snap = PluginDriftSnapshot(manifest: manifest!, workingFiles: workingFiles)
        drift = snap
        sourceCommitShort = snap.manifest.shortCommit
        lastRefresh = Date()
        lastInstallError = nil
    }

    @MainActor
    func reinstall(reason: String = "via harness-app reinstall", takeSnapshot: Bool = true) async {
        isInstalling = true
        defer { isInstalling = false }
        lastInstallError = nil

        let script = URL(fileURLWithPath: HarnessClient.home.path)
            .appendingPathComponent("Code/harness-self-improvement/install.sh", conformingTo: .text)

        guard FileManager.default.isExecutableFile(atPath: script.path) else {
            lastInstallError = "install.sh not found or not executable at \(script.path)"
            return
        }

        var args = [String]()
        if !takeSnapshot { args.append("--no-snapshot") }

        let r = await HarnessClient.run(
            command: ["/bin/bash", script.path] + args,
            cwd: URL(fileURLWithPath: HarnessClient.home.path)
                .appendingPathComponent("Code/harness-self-improvement", conformingTo: .directory)
        )
        if !r.ok {
            lastInstallError = "install.sh failed: \(r.stderr.prefix(240))"
            return
        }
        refresh()
    }

    /// Run install.sh --check and capture its output. Non-destructive.
    @MainActor
    func checkDrift() async -> String {
        let script = URL(fileURLWithPath: HarnessClient.home.path)
            .appendingPathComponent("Code/harness-self-improvement/install.sh", conformingTo: .text)
        let r = await HarnessClient.run(
            command: ["/bin/bash", script.path, "--check"],
            cwd: URL(fileURLWithPath: HarnessClient.home.path)
                .appendingPathComponent("Code/harness-self-improvement", conformingTo: .directory)
        )
        return r.stdout + (r.stderr.isEmpty ? "" : "\n\(r.stderr)")
    }

    // MARK: - Hashing

    private func sha256(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private func readManifest() -> PluginInstallManifest? {
        let url = HarnessClient.ncodeDir.appendingPathComponent(".harness.installed.json", conformingTo: .text)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PluginInstallManifest.self, from: data)
    }

    private func collectDrift() -> [String: DriftTriple] {
        guard let m = manifest else { return [:] }
        let sourceScriptsDir = URL(fileURLWithPath: HarnessClient.home.path)
            .appendingPathComponent("Code/harness-self-improvement/scripts", conformingTo: .directory)
        let liveScriptsDir = HarnessClient.ncodeDir
            .appendingPathComponent("plugins/marketplaces/harness-local/scripts", conformingTo: .directory)

        var out: [String: DriftTriple] = [:]
        for entry in m.files {
            let fileName = (entry.path as NSString).lastPathComponent
            let sourceHash = sha256(at: sourceScriptsDir.appendingPathComponent(fileName, conformingTo: .text))
            let liveHash = sha256(at: liveScriptsDir.appendingPathComponent(fileName, conformingTo: .text))
            out[entry.path] = DriftTriple(
                installed: entry.sha256,
                source: sourceHash,
                live: liveHash
            )
        }
        return out
    }
}
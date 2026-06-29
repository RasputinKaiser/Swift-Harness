import Foundation
import CryptoKit

/// Decoded entry from ~/.ncode/.harness.installed.json, written by `install.sh`.
struct PluginInstallManifest: Codable, Hashable {
    let commit: String
    let branch: String
    let installedAt: String
    let hooksSha256: String
    let marketplaceJsonSha256: String
    let pluginJsonSha256: String
    let files: [Entry]

    struct Entry: Hashable, Codable {
        let path: String  // e.g. "scripts/autonomy_gate.py"
        let sha256: String
    }

    var shortCommit: String { String(commit.prefix(8)) }
    var installedAtDate: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: installedAt) ?? ISO8601DateFormatter().date(from: installedAt)
    }
}

/// Drift between source repo, last install manifest, and live install cache.
struct PluginDriftSnapshot: Identifiable {
    let id = UUID()
    let manifest: PluginInstallManifest
    let workingFiles: [String: DriftTriple]  // path -> (installed, source, live)
    var changedCount: Int { workingFiles.values.filter { $0.drifted }.count }
    var missingInSourceCount: Int { workingFiles.values.filter { $0.source == nil }.count }
    var missingInLiveCount: Int { workingFiles.values.filter { $0.live == nil }.count }
}

struct DriftTriple: Hashable {
    let installed: String  // sha256 from manifest
    let source: String?    // sha256 in git working copy
    let live: String?      // sha256 in install cache
    var drifted: Bool {
        guard let s = source else { return true }  // file gone in source = drift
        return s != installed || (live != nil && live != installed)
    }
    var status: Status {
        if source == nil { return .goneFromSource }
        if live == nil { return .goneFromLive }
        if source != installed { return .sourceChanged }
        if live != installed { return .liveChanged }
        return .inSync
    }
    enum Status: String, Hashable {
        case inSync,         sourceChanged,      liveChanged,
             goneFromSource, goneFromLive
        var label: String { rawValue }
        var icon: String {
            switch self {
            case .inSync: "checkmark.circle.fill"
            case .sourceChanged: "arrow.triangle.2.circlepath"
            case .liveChanged: "exclamationmark.triangle.fill"
            case .goneFromSource: "minus.circle.fill"
            case .goneFromLive: "magnifyingglass.circle"
            }
        }
        var tint: String {
            switch self {
            case .inSync: "green"
            case .sourceChanged: "orange"
            case .liveChanged: "yellow"
            case .goneFromSource: "gray"
            case .goneFromLive: "red"
            }
        }
    }
}
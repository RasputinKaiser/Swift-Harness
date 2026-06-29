import Foundation
import Observation

/// Tracks which panes are selected over time — persisted to
/// ~/.ncode/usage-data/pane-usage.json for trend analysis.
///
/// After 2 weeks of data, the bottom 25% of panes can be considered
/// for removal or folding into parent panes.
@Observable
final class PaneUsageTracker {

    private(set) var counts: [String: Int] = [:]
    private let path: URL

    init() {
        let dir = HarnessClient.ncodeDir.appendingPathComponent("usage-data", conformingTo: .directory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        path = dir.appendingPathComponent("pane-usage.json", conformingTo: .text)
        load()
    }

    func track(_ section: String) {
        counts[section, default: 0] += 1
        persist()
    }

    var totalSelections: Int { counts.values.reduce(0, +) }
    var paneRankings: [(pane: String, count: Int)] {
        counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: path),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Int] else {
            return
        }
        counts = dict
    }

    private func persist() {
        guard let data = try? JSONSerialization.data(withJSONObject: counts, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: path)
    }
}
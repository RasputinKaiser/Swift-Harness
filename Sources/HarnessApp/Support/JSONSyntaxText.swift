import SwiftUI

/// Renders a JSON-looking string with simple syntax coloring.
///
/// Colorizes keys (blue), string values (green), numbers (orange), and
/// booleans/null (purple) using AttributedString. Used by the session
/// transcript viewer to color raw JSONL events.
///
/// Performance: compiled regexes are cached as static constants (compiled
/// once, not per render). Colorized AttributedString is memoized per input
/// string in a bounded static cache — re-renders of the same JSON line
/// return the cached result without regex matching.
struct JSONSyntaxText: View {
    let raw: String

    init(_ raw: String) { self.raw = raw }

    var body: some View {
        if let attributed = JSONSyntaxText.colorized(raw) {
            Text(attributed)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(raw)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(8)
        }
    }

    // MARK: - Shared (compiled once)

    private static let keyRegex = try? NSRegularExpression(
        pattern: #"("([^"\\]|\\.)*")(\s*:)"#)
    private static let stringRegex = try? NSRegularExpression(
        pattern: #":\s*("([^"\\]|\\.)*")"#)
    private static let numberRegex = try? NSRegularExpression(
        pattern: #"\b-?\d+(\.\d+)?\b"#)
    private static let boolRegex = try? NSRegularExpression(
        pattern: #"\b(true|false|null)\b"#)

    private static let keyColor: Color = .blue
    private static let stringColor: Color = .green
    private static let numberColor: Color = .orange
    private static let boolColor: Color = .purple

    // Bounded cache: prevents re-computing the same JSON line repeatedly.
    // Capped at 200 entries (covers most visible transcript rows + some scrollback).
    private static var cache: [String: AttributedString] = [:]
    private static let cacheLimit = 200

    private static func colorized(_ raw: String) -> AttributedString? {
        if let cached = cache[raw] { return cached }

        guard raw.hasPrefix("{") || raw.hasPrefix("[") else { return nil }

        var attr = AttributedString(raw)
        let nsString = raw as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        // Apply each pattern — find matches, then color the matched range.
        // Uses range-based coloring directly (no substring search).
        let patterns: [(NSRegularExpression?, Color)] = [
            (keyRegex, keyColor),
            (stringRegex, stringColor),
            (numberRegex, numberColor),
            (boolRegex, boolColor),
        ]
        for (regex, color) in patterns {
            guard let regex else { continue }
            let matches = regex.matches(in: raw, range: fullRange)
            for m in matches where m.numberOfRanges > 0 {
                let r = m.range
                // Convert NSRange to AttributedString range via UTF-16 offsets
                if let start = attr.index(attr.startIndex,
                                         offsetByCharacters: r.location),
                   let end = attr.index(start,
                                        offsetByCharacters: r.length) {
                    attr[start..<end].foregroundColor = color
                }
            }
        }

        if cache.count >= cacheLimit {
            // Evict ~25% of entries (oldest not tracked — just clear all)
            cache.removeAll(keepingCapacity: false)
        }
        cache[raw] = attr
        return attr
    }
}

private extension AttributedString {
    /// Offset the index by N UTF-16 code units (matches NSString range semantics).
    func index(_ i: AttributedString.Index, offsetByCharacters n: Int) -> AttributedString.Index? {
        if n == 0 { return i }
        var current = i
        var remaining = n
        if n > 0 {
            while remaining > 0 && current < endIndex {
                current = index(afterCharacter: current)
                remaining -= 1
            }
        } else {
            while remaining < 0 && current > startIndex {
                current = index(beforeCharacter: current)
                remaining += 1
            }
        }
        return remaining == 0 ? current : nil
    }
}
import SwiftUI

/// Renders a JSON-looking string with simple syntax coloring.
///
/// Colorizes keys (blue), string values (green), numbers (orange), and
/// booleans/null (purple) using AttributedString. Used by the session
/// transcript viewer to color raw JSONL events.
struct JSONSyntaxText: View {
    let raw: String

    init(_ raw: String) {
        self.raw = raw
    }

    var body: some View {
        if let attributed = colorized {
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

    private var colorized: AttributedString? {
        // Regex matching JSON tokens: "key":, "string", number, true|false|null
        // Apply color attributes per token type.
        var attr = AttributedString(raw)
        let patterns: [(String, Color)] = [
            (#"("([^"\\]|\\.)*")(\s*:)"#, .blue),                 // keys (string followed by colon)
            (#":\s*("([^"\\]|\\.)*")"#, .green),                  // string values
            (#"\b-?\d+(\.\d+)?\b"#, .orange),                    // numbers
            (#"\b(true|false|null)\b"#, .purple),                // booleans/null
        ]
        for (pattern, color) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsString = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: nsString.length))
            for m in matches where m.numberOfRanges > 0 {
                let r = m.range
                if let range = attr.range(of: nsString.substring(with: r),
                                         options: [],
                                         locale: nil) {
                    attr[range].foregroundColor = color
                }
            }
        }
        return attr
    }
}
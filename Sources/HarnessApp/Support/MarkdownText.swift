import SwiftUI

/// Renders text with simple code-fence handling.
///
/// Splits content on triple-backtick (```) fences. Segments inside fences are
/// rendered as a code block with a tinted background + monospaced font; text
/// outside fences renders as body text. Falls back to plain body Text when no
/// fences are present.
struct MarkdownText: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        let segments = parseSegments()
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment.kind {
                case .text:
                    Text(segment.text)
                        .font(.system(.body))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code:
                    VStack(alignment: .leading, spacing: 0) {
                        Text(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.purple.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.purple.opacity(0.15), lineWidth: 1)
                    )
                }
            }
        }
    }

    private enum SegmentKind { case text, code }
    private struct Segment { let kind: SegmentKind; let text: String }

    private func parseSegments() -> [Segment] {
        var segments: [Segment] = []
        var current = ""
        var inCode = false
        let lines = content.components(separatedBy: "\n")
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                // Fence toggle
                if !current.isEmpty {
                    segments.append(Segment(kind: inCode ? .code : .text, text: current))
                    current = ""
                }
                inCode.toggle()
                continue
            }
            current += (current.isEmpty ? "" : "\n") + line
        }
        if !current.isEmpty {
            segments.append(Segment(kind: inCode ? .code : .text, text: current))
        }
        return segments
    }
}
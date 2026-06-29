import SwiftUI

/// Tiny line-chart sparkline for trend visualization in headers/cards.
///
/// Renders the values as a normalized line in a fixed height; no axis labels
/// or grid. Use for compact trend previews alongside larger status displays.
///
/// ```swift
/// Sparkline(values: [0.4, 0.9, 0.8, 1.0, 0.6], color: .green)
///     .frame(width: 80, height: 18)
/// ```
struct Sparkline: View {
    let values: [Double]
    let color: Color
    let lineWidth: CGFloat

    init(values: [Double], color: Color = .accentColor, lineWidth: CGFloat = 1.5) {
        self.values = values
        self.color = color
        self.lineWidth = lineWidth
    }

    var body: some View {
        GeometryReader { geo in
            if values.count < 2 {
                if values.count == 1 {
                    Circle()
                        .fill(color)
                        .frame(width: lineWidth * 2, height: lineWidth * 2)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                } else {
                    EmptyView()
                }
            } else {
                Path { path in
                    let w = geo.size.width
                    let h = geo.size.height
                    let n = values.count
                    let stepX = w / CGFloat(n - 1)
                    for (i, v) in values.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = h - (CGFloat(v) * h)
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
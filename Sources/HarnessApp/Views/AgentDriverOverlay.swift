import SwiftUI
import WebKit

/// Overlay shown on top of the WKWebView when the agent is driving it.
/// Renders yellow highlight rings at click coordinates and a "Agent driving"
/// badge in the corner.
struct AgentDriverOverlay: View {
    let highlights: [ClickHighlight]
    let isDriving: Bool

    struct ClickHighlight: Identifiable {
        let id = UUID()
        let rect: CGRect
        let createdAt: Date
    }

    var body: some View {
        ZStack {
            // Click highlights — pulse and fade
            ForEach(highlights) { h in
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.yellow, lineWidth: 3)
                    .opacity(opacity(h))
                    .frame(width: h.rect.width, height: h.rect.height)
                    .position(x: h.rect.midX, y: h.rect.midY)
                    .shadow(color: .yellow.opacity(0.4), radius: 4)
            }

            // Agent driving badge (top-right corner)
            if isDriving {
                VStack {
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.caption.bold())
                        Text("Agent driving")
                            .font(.caption2.bold())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.2), in: Capsule())
                    .overlay(
                        Capsule().stroke(.orange, lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(8)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isDriving)
        .animation(.easeOut(duration: 0.3), value: highlights.count)
        .allowsHitTesting(false)
    }

    private func opacity(_ h: ClickHighlight) -> Double {
        let age = Date().timeIntervalSince(h.createdAt)
        if age < 0.5 { return 1.0 }
        if age < 1.0 { return 0.7 }
        if age < 1.5 { return 0.3 }
        return 0
    }
}
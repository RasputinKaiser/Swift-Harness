import SwiftUI
import WebKit

/// Split-view combining Chat (left) + an embedded Browser (right).
///
/// The browser is a companion surface — you chat with NCode on the left while
/// a URL is open on the right. The chat pane can suggest URLs that land in the
/// browser via the `browserURL` binding, and the user can navigate freely
/// without leaving the conversation surface.
///
/// Modeled on Codex's in-app browser + chat layout.
struct ChatSplitView: View {
    @Environment(HarnessStore.self) private var store
    @State private var urlInput: String = ""
    @AppStorage("chatSplitFraction") private var chatSplitFraction: Double = 0.5

    var body: some View {
        HSplitView {
            ChatPane()
                .frame(minWidth: 380, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            companionBrowser
                .frame(minWidth: 380, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if store.browserModel.url == nil {
                store.browserModel.load(URL(string: "https://github.com/RasputinKaiser/Self-Improvement-Plugin")!)
            }
        }
    }

    @ViewBuilder
    private var companionBrowser: some View {
        VStack(spacing: 0) {
            browserToolbar
            Divider()
            ZStack(alignment: .topTrailing) {
                WebView(webView: store.browserModel)
                AgentDriverOverlay(
                    highlights: store.browserModel.clickHighlights,
                    isDriving: store.browserModel.isAgentDriving
                )
            }
            Divider()
            browserFooter
        }
    }

    private var browserToolbar: some View {
        HStack(spacing: 8) {
            Button { store.browserModel.goBack() } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!store.browserModel.canGoBack)
            .buttonStyle(.borderless)

            Button { store.browserModel.goForward() } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!store.browserModel.canGoForward)
            .buttonStyle(.borderless)

            Button { store.browserModel.reload() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)

            TextField("URL or search…", text: $urlInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if let url = resolveURL(urlInput) {
                        store.browserModel.load(url)
                        urlInput = ""
                    }
                }

            if store.browserModel.isLoading {
                ProgressView().controlSize(.small)
            }

            // Agent driver toggle
            Button {
                store.browserModel.isAgentDriving.toggle()
            } label: {
                Image(systemName: store.browserModel.isAgentDriving ? "sparkles" : "hand.tap")
                    .foregroundStyle(store.browserModel.isAgentDriving ? .orange : .secondary)
            }
            .buttonStyle(.borderless)
            .help(store.browserModel.isAgentDriving ? "Agent driving — press Cmd+. to stop" : "Allow agent to drive browser")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var browserFooter: some View {
        HStack(spacing: 6) {
            if store.browserModel.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            Text(store.browserModel.url?.host ?? "(no page loaded)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let title = store.browserModel.title, !title.isEmpty {
                Text(title.prefix(40))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.thinMaterial)
    }

    private func resolveURL(_ s: String) -> URL? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") { return URL(string: trimmed) }
        if trimmed.contains(".") && !trimmed.contains(" ") {
            return URL(string: "https://\(trimmed)")
        }
        return URL(string: "https://www.google.com/search?q=\(trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed)")
    }
}

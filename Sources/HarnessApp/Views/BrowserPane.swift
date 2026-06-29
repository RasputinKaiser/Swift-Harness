import SwiftUI
import WebKit
import AppKit

struct BrowserPane: View {
    @State private var urlText: String = "https://github.com/RasputinKaiser/Self-Improvement-Plugin"
    @State private var webView = WebViewModel()
    @FocusState private var urlFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            WebView(webView: webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            statusBar
        }
        .navigationTitle("Browser")
        .onAppear { webView.load(URL(string: urlText)!) }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { webView.goBack() } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!webView.canGoBack)
            Button { webView.goForward() } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!webView.canGoForward)
            Button { webView.reload() } label: {
                Image(systemName: "arrow.clockwise")
            }
            Button { webView.stopLoading() } label: {
                Image(systemName: "xmark")
            }
            .opacity(webView.isLoading ? 1 : 0.3)
            .disabled(!webView.isLoading)

            TextField("URL", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if let url = resolveURL(urlText) {
                        webView.load(url)
                    }
                }
                .focused($urlFieldFocused)
                .onAppear {
                    // Highlight URL text on first appear so user can edit fast
                    DispatchQueue.main.async { urlFieldFocused = true }
                }

            Button {
                if let url = (webView.url?.absoluteString) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .disabled(webView.url == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if webView.isLoading {
                ProgressView().controlSize(.small)
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
                Text("Loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let u = webView.url {
                Text(u.host ?? "")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }

    private func resolveURL(_ s: String) -> URL? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }
}

// MARK: - WebViewModel

@Observable
final class WebViewModel {
    var url: URL?
    var isLoading = false
    var title: String?
    var canGoBack = false
    var canGoForward = false
    var estimatedProgress: Double = 0

    /// Agent driver state — true when the agent is actively controlling the browser
    var isAgentDriving = false
    /// Click highlights for the AgentDriverOverlay — capped at 5, auto-expired
    var clickHighlights: [AgentDriverOverlay.ClickHighlight] = []

    @ObservationIgnored weak var webView: WKWebView?
    private var observers: [NSKeyValueObservation] = []

    func attach(_ wv: WKWebView) {
        webView = wv
        observers.append(wv.observe(\.url, options: [.new]) { [weak self] _, change in
            Task { @MainActor in self?.url = change.newValue ?? nil }
        })
        observers.append(wv.observe(\.isLoading, options: [.new]) { [weak self] _, change in
            Task { @MainActor in self?.isLoading = change.newValue ?? false }
        })
        observers.append(wv.observe(\.title, options: [.new]) { [weak self] _, change in
            Task { @MainActor in self?.title = change.newValue ?? "" }
        })
        observers.append(wv.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
            Task { @MainActor in self?.canGoBack = change.newValue ?? false }
        })
        observers.append(wv.observe(\.canGoForward, options: [.new]) { [weak self] _, change in
            Task { @MainActor in self?.canGoForward = change.newValue ?? false }
        })
        observers.append(wv.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
            let newValue = change.newValue ?? 0
            // Throttle: skip if delta < 5%. Reduces ~20-30 main-thread Task
            // hops per page load to ~5-10. ProgressView already interpolates.
            if let self {
                let delta = abs(newValue - self.estimatedProgress)
                if delta >= 0.05 || newValue == 0 || newValue >= 1.0 {
                    Task { @MainActor in self.estimatedProgress = newValue }
                }
            }
        })
    }

    func load(_ url: URL) {
        webView?.load(URLRequest(url: url))
        self.url = url
    }
    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func stopLoading() { webView?.stopLoading() }

    @MainActor
    func addClickHighlight(_ rect: CGRect) {
        clickHighlights.append(AgentDriverOverlay.ClickHighlight(rect: rect, createdAt: Date()))
        if clickHighlights.count > 5 {
            clickHighlights.removeFirst(clickHighlights.count - 5)
        }
        // Auto-remove after 2s
        let id = clickHighlights.last?.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if let id { clickHighlights.removeAll { $0.id == id } }
        }
    }
}

// MARK: - NSViewRepresentable wrapper

struct WebView: NSViewRepresentable {
    let webView: WebViewModel

    func makeNSView(context: Context) -> WKWebView {
        // Config: enable JavaScript, modern user agent, safe defaults for dev/research
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.suppressesIncrementalRendering = false

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsMagnification = true
        #if DEBUG
        if #available(macOS 13.3, *) {
            wv.isInspectable = true
        }
        #endif
        webView.attach(wv)
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        // No-op: state changes flow observation-driven into the model.
    }
}

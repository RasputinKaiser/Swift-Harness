import Foundation
import WebKit

/// WKNavigationDelegate coordinator that resumes a continuation when
/// navigation completes or fails. Used by `WebViewModel.navigate(to:)`.
final class NavigationCoordinator: NSObject, WKNavigationDelegate {

    private var continuation: CheckedContinuation<NavResult, Never>?
    private var timeoutTask: Task<Void, Never>?

    struct NavResult {
        let url: String
        let title: String
        let succeeded: Bool
        let error: String?
    }

    func navigate(_ webView: WKWebView, to url: URL) async -> NavResult {
        // Cancel any pending navigation continuation
        continuation?.resume(returning: NavResult(url: "", title: "", succeeded: false, error: "superseded"))
        continuation = nil
        timeoutTask?.cancel()

        webView.navigationDelegate = self
        return await withCheckedContinuation { cont in
            self.continuation = cont
            webView.load(URLRequest(url: url))

            // Timeout after 8 seconds — resume with partial result
            self.timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { return }
                if let cont = self.continuation {
                    self.continuation = nil
                    let url = webView.url?.absoluteString ?? url.absoluteString
                    let title = webView.title ?? ""
                    cont.resume(returning: NavResult(url: url, title: title,
                                                     succeeded: false,
                                                     error: "navigation timeout (8s)"))
                }
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel()
        let url = webView.url?.absoluteString ?? ""
        let title = webView.title ?? ""
        cont.resume(returning: NavResult(url: url, title: title, succeeded: true, error: nil))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel()
        cont.resume(returning: NavResult(url: "", title: "", succeeded: false,
                                          error: error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel()
        cont.resume(returning: NavResult(url: "", title: "", succeeded: false,
                                          error: error.localizedDescription))
    }
}

// MARK: - WebViewModel async extensions

extension WebViewModel {

    /// Navigate to a URL and wait for completion (or 8s timeout).
    @MainActor
    func navigate(to url: URL) async -> NavigationCoordinator.NavResult {
        guard let wv = webView else {
            return NavigationCoordinator.NavResult(url: "", title: "", succeeded: false,
                                                    error: "WKWebView not attached")
        }
        let coordinator = NavigationCoordinator()
        return await coordinator.navigate(wv, to: url)
    }

    /// Execute JavaScript in the WKWebView. Returns the result as a string.
    @MainActor
    func evalJS(_ js: String) async -> (result: String?, error: String?) {
        guard let wv = webView else {
            return (nil, "WKWebView not attached")
        }
        return await withCheckedContinuation { cont in
            wv.evaluateJavaScript(js) { result, error in
                if let error = error {
                    cont.resume(returning: (nil, error.localizedDescription))
                } else if let result = result {
                    if let s = result as? String {
                        cont.resume(returning: (s, nil))
                    } else if let data = try? JSONSerialization.data(withJSONObject: result, options: []),
                              let s = String(data: data, encoding: .utf8) {
                        cont.resume(returning: (s, nil))
                    } else {
                        cont.resume(returning: (String(describing: result), nil))
                    }
                } else {
                    cont.resume(returning: ("null", nil))
                }
            }
        }
    }

    /// Extract DOM elements matching a CSS selector. Returns HTML, text, and count.
    @MainActor
    func extract(selector: String, attr: String?) async -> (html: String, text: String, count: Int) {
        let attrJS = attr != nil ? "el.getAttribute('\(attr!)')" : "el.outerHTML"
        let js = """
        (function() {
            var els = document.querySelectorAll(\(selector.replacingOccurrences(of: "'", with: "\\'")));
            var results = [];
            var texts = [];
            for (var i = 0; i < els.length; i++) {
                results.push(\(attrJS));
                texts.push(els[i].innerText);
            }
            return JSON.stringify({html: results.join('\\n'), text: texts.join('\\n'), count: results.length});
        })()
        """
        let (result, error) = await evalJS(js)
        if let error = error {
            return (html: "", text: "", count: 0)
        }
        guard let result = result,
              let data = result.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (html: result ?? "", text: "", count: 0)
        }
        let html = (dict["html"] as? String) ?? ""
        let text = (dict["text"] as? String) ?? ""
        let count = (dict["count"] as? Int) ?? 0
        return (html: html, text: text, count: count)
    }
}
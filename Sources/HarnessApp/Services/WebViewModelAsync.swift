import Foundation
import AppKit
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

    /// Click an element matching a CSS selector. Scrolls into view first,
    /// dispatches a synthetic click via JS, and returns the bounding rect
    /// so the caller can show an overlay highlight.
    @MainActor
    func click(selector: String) async -> (clicked: Bool, rect: CGRect?, error: String?) {
        guard let wv = webView else {
            return (false, nil, "WKWebView not attached")
        }
        // JS: scroll into view + get bounding rect + click
        let js = """
        (function() {
            var el = document.querySelector('\(selector.replacingOccurrences(of: "'", with: "\\'"))');
            if (!el) return JSON.stringify({found: false});
            el.scrollIntoView({behavior: 'instant', block: 'center'});
            var rect = el.getBoundingClientRect();
            el.click();
            return JSON.stringify({
                found: true,
                clicked: true,
                x: rect.x, y: rect.y, width: rect.width, height: rect.height
            });
        })()
        """
        let (result, error) = await evalJS(js)
        if let error = error {
            return (false, nil, error)
        }
        guard let result = result,
              let data = result.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (false, nil, "failed to parse click result")
        }
        guard dict["found"] as? Bool == true else {
            return (false, nil, "element not found for selector: \(selector)")
        }
        let x = (dict["x"] as? Double) ?? 0
        let y = (dict["y"] as? Double) ?? 0
        let width = (dict["width"] as? Double) ?? 0
        let height = (dict["height"] as? Double) ?? 0
        return (true, CGRect(x: x, y: y, width: width, height: height), nil)
    }

    /// Screenshot the current WKWebView (or a selector-scoped region).
    /// Writes the PNG to a cache file and returns the path + base64 (if < 200KB).
    @MainActor
    func screenshot(selector: String?, maxWidth: Int?) async -> (path: String?, width: Int, height: Int, b64: String?, b64Truncated: Bool, error: String?) {
        guard let wv = webView else {
            return (nil, 0, 0, nil, false, "WKWebView not attached")
        }

        let config = WKSnapshotConfiguration()
        // Full-page snapshot (selector-scoped cropping deferred to Phase 4)
        config.afterScreenUpdates = true

        let image: NSImage = await withCheckedContinuation { cont in
            wv.takeSnapshot(with: config) { img, _ in
                cont.resume(returning: img ?? NSImage())
            }
        }

        // Scale if maxWidth specified
        var finalImage = image
        if let maxW = maxWidth, Int(image.size.width) > maxW {
            let scale = CGFloat(maxW) / image.size.width
            let newSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let scaled = NSImage(size: newSize)
            scaled.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize))
            scaled.unlockFocus()
            finalImage = scaled
        }

        guard let tiffData = finalImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return (nil, 0, 0, nil, false, "failed to create PNG")
        }

        // Write to cache dir
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("HarnessApp/screenshots", conformingTo: .directory)
        if let cacheDir {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        let filename = "screenshot_\(UUID().uuidString.prefix(8)).png"
        let filePath = (cacheDir ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent(filename, conformingTo: .text)
        do {
            try pngData.write(to: filePath)
        } catch {
            return (nil, 0, 0, nil, false, "write failed: \(error.localizedDescription)")
        }

        let width = Int(finalImage.size.width)
        let height = Int(finalImage.size.height)

        // Dual-channel: embed base64 if < 200KB
        let maxB64 = 200 * 1024
        let b64String = pngData.base64EncodedString()
        if b64String.count < maxB64 {
            return (filePath.path, width, height, b64String, false, nil)
        } else {
            return (filePath.path, width, height, nil, true, nil)
        }
    }
}
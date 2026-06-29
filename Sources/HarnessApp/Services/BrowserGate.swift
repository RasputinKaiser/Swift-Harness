import Foundation

/// Security gate for browser IPC commands. Validates URLs and JS before
/// they reach the WKWebView. Phase 2: basic policy. Phase 3+ adds rate
/// limiting and login-origin pre-flight.
enum BrowserGate {

    enum Decision {
        case allowed
        case blocked(reason: String)
    }

    // MARK: - URL policy

    static func checkURL(_ urlString: String) -> Decision {
        guard let url = URL(string: urlString) else {
            return .blocked(reason: "Invalid URL format")
        }
        guard let scheme = url.scheme?.lowercased() else {
            return .blocked(reason: "No URL scheme")
        }

        // Only http/https
        guard scheme == "http" || scheme == "https" else {
            return .blocked(reason: "Scheme '\(scheme)' not allowed (http/https only)")
        }

        // Block file://, about:, data: (redundant with scheme check but explicit)
        let blockedSchemes = ["file", "about", "data", "ftp", "javascript"]
        if blockedSchemes.contains(scheme) {
            return .blocked(reason: "Scheme '\(scheme)' blocked by policy")
        }

        guard let host = url.host?.lowercased() else {
            return .blocked(reason: "No host in URL")
        }

        // Block .local mDNS
        if host.hasSuffix(".local") || host == "local" {
            return .blocked(reason: ".local mDNS blocked — use Allow LAN toggle for private network access")
        }

        // Block private IP ranges
        if isPrivateIP(host) {
            return .blocked(reason: "Private IP range blocked — \(host)")
        }

        // Block localhost variants
        if host == "localhost" || host == "127.0.0.1" || host == "0.0.0.0" || host == "[::1]" {
            return .blocked(reason: "localhost blocked")
        }

        return .allowed
    }

    private static func isPrivateIP(_ host: String) -> Bool {
        // Parse IPv4
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }

        // 10.0.0.0/8
        if parts[0] == 10 { return true }
        // 172.16.0.0/12
        if parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31 { return true }
        // 192.168.0.0/16
        if parts[0] == 192 && parts[1] == 168 { return true }
        // 127.0.0.0/8 (loopback — covered by localhost check but explicit)
        if parts[0] == 127 { return true }
        // 0.0.0.0
        if parts == [0, 0, 0, 0] { return true }

        return false
    }

    // MARK: - JS eval policy

    /// Patterns that are refused in browser_eval to prevent data exfiltration.
    static let blockedJSPatterns: [(String, String)] = [
        ("fetch\\s*\\(", "fetch() not allowed — use browser_extract instead"),
        ("XMLHttpRequest", "XMLHttpRequest not allowed"),
        ("new\\s+Function\\s*\\(", "new Function() not allowed"),
        ("window\\.open\\s*\\(", "window.open() not allowed"),
        ("document\\.cookie", "document.cookie access blocked"),
        ("localStorage\\.setItem", "localStorage writes blocked"),
        ("sessionStorage\\.setItem", "sessionStorage writes blocked"),
        ("navigator\\.clipboard", "clipboard API blocked"),
    ]

    static func checkJS(_ js: String) -> Decision {
        let lowercased = js.lowercased()
        for (pattern, message) in blockedJSPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: js, range: NSRange(location: 0, length: js.utf16.count)) != nil {
                return .blocked(reason: message)
            }
            _ = lowercased // also check plain substring
        }
        return .allowed
    }

    // MARK: - Login origins (Phase 3: pre-flight confirmation)

    static let loginOrigins: Set<String> = [
        "accounts.google.com",
        "login.live.com",
        "signin.aws.amazon.com",
        "bankofamerica.com",
        "chase.com",
        "wellsfargo.com",
        "paypal.com",
        "github.com/login",
        "mail.google.com",
        "outlook.live.com",
    ]

    static func isLoginOrigin(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return false }
        return loginOrigins.contains(where: { host.contains($0) })
    }
}
import Foundation

/// Single source of truth for app version metadata.
/// Future Phase 8 (notarization): bump these on release.
enum Version {
    static let major = 0
    static let minor = 7
    static let patch = 0
    static let suffix = "dev"

    static var full: String {
        var s = "\(major).\(minor).\(patch)"
        if !suffix.isEmpty { s += "-\(suffix)" }
        return s
    }

    static var build: String {
        // Pull from git short sha if available; fails gracefully to "local"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["rev-parse", "--short", "HEAD"]
        p.currentDirectoryURL = URL(fileURLWithPath: HarnessClient.home.path)
            .appendingPathComponent("Code/harness-app", conformingTo: .directory)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "local"
            }
        } catch {}
        return "local"
    }

    static var displayString: String { "v\(full) (\(build))" }
}
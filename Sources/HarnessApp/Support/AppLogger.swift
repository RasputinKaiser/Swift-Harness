import Foundation
import os

/// Thin wrapper around `os.Logger` with a stable subsystem for the app.
/// All tailers and streamers log here — even when stdout/stderr aren't visible
/// (which is the case once the app is launched via Finder).
///
/// Usage:
///     AppLogger.shared.file("transcript not found", url: url)
///     AppLogger.shared.process("hook tap spawn failed", exitCode: 1)
enum AppLogger {
    static let subsystem = "com.rasputinkaiser.harnessapp"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let file = Logger(subsystem: subsystem, category: "file")
    static let process = Logger(subsystem: subsystem, category: "process")
    static let tailer = Logger(subsystem: subsystem, category: "tailer")
    static let streamer = Logger(subsystem: subsystem, category: "streamer")
    static let hookEvents = Logger(subsystem: subsystem, category: "hook-events")
    static let session = Logger(subsystem: subsystem, category: "session")

    /// One-shot bootstrap call — surface a single log line at app launch
    /// so users can confirm the app started. Cheap to call multiple times.
    static func bootstrap() {
        general.notice("harness-app \(Version.displayString) launched")
    }
}
import Foundation
import Observation

/// `@Observable` session-tailer: monitors a transcript JSONL file via
/// `DispatchSource.makeFileSystemObjectSource`, parses each new line into a
/// typed `ActivityEvent`, and appends to an in-memory ring (capped at `maxEvents`).
///
/// File I/O happens on a private serial queue; mutations are dispatched back to
/// `MainActor` to keep SwiftUI safe.
@Observable
final class SessionActivityStore {

    /// Max events before oldest is dropped. Keeps memory bounded for multi-hour sessions.
    var maxEvents = 500

    /// Reverse-chronological? false = oldest -> newest (chronological), true = newest first.
    var newestFirst = false

    /// The currently-attached session, if any.
    private(set) var attachedSession: SessionDescriptor?

    /// Events sorted by `newestFirst`.
    private(set) var events: [ActivityEvent] = []

    /// Last raw line index processed — used to know what's already in `events`.
    private(set) var totalEventsObserved = 0

    /// Live status banner.
    private(set) var status: AttachStatus = .idle

    enum AttachStatus: Equatable {
        case idle
        case attaching(URL)
        case tailing(URL)
        case failed(String)
        case finished(URL)
    }

    // MARK: - Lifecycle

    init() {}

    @MainActor
    func attach(to session: SessionDescriptor) {
        detach()
        let url = session.transcriptURL
        status = .attaching(url)
        attachedSession = session
        events = []
        totalEventsObserved = 0
        beginTailing(url: url)
    }

    @MainActor
    func detach() {
        dispatchSource?.cancel()
        dispatchSource = nil
        fileHandle?.closeFile()
        fileHandle = nil
        offset = 0
    }

    // MARK: - Tail internals (NOT MainActor — private serial queue)

    private var fileHandle: FileHandle?
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var offset: UInt64 = 0
    private let ioQueue = DispatchQueue(label: "com.rasputinkaiser.harnessapp.session-tailer")

    private func beginTailing(url: URL) {
        ioQueue.async { [weak self] in
            guard let self else { return }

            // If the file doesn't exist yet, mark failed (can re-attempt via attach).
            guard FileManager.default.fileExists(atPath: url.path) else {
                Task { @MainActor in
                    self.status = .failed("Transcript not found: \(url.lastPathComponent)")
                }
                return
            }

            guard let fh = try? FileHandle(forReadingFrom: url) else {
                Task { @MainActor in
                    self.status = .failed("Could not open transcript")
                }
                return
            }

            // Seek to end so we don't replay the entire history. (Phase 1.1 tweak:
            // could add a "--replay-history" toggle later.)
            let endOffset = (try? fh.seekToEnd()) ?? 0
            offset = endOffset
            try? fh.seek(toOffset: offset)

            // Drain everything written between seekToEnd and now (small race window).
            self.drain(from: fh, url: url)

            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fh.fileDescriptor,
                eventMask: [.write, .extend, .delete],
                queue: self.ioQueue
            )
            src.setEventHandler { [weak self] in
                guard let self else { return }
                self.drain(from: fh, url: url)
                if src.data.contains(.delete) {
                    src.cancel()
                    Task { @MainActor in self.status = .finished(url) }
                }
            }
            src.setCancelHandler {
                fh.closeFile()
            }
            src.resume()

            Task { @MainActor in
                self.fileHandle = fh
                self.dispatchSource = src
                self.status = .tailing(url)
            }
        }
    }

    private func drain(from fh: FileHandle, url: URL) {
        let currentSize = (try? fh.seekToEnd()) ?? 0
        guard currentSize > offset else { return }
        try? fh.seek(toOffset: offset)
        guard let data = try? fh.read(upToCount: Int(currentSize - offset)) else { return }
        offset = currentSize

        var lines: [String] = []
        var pending = Data()
        for byte in data {
            if byte == 0x0A {
                if let s = String(data: pending, encoding: .utf8) { lines.append(s) }
                pending.removeAll()
            } else {
                pending.append(byte)
            }
        }
        if !pending.isEmpty, let s = String(data: pending, encoding: .utf8) { lines.append(s) }

        let parsed = lines.compactMap { ActivityEvent.parse($0) }
        guard !parsed.isEmpty else { return }

        Task { @MainActor in
            self.append(parsed)
        }
    }

    @MainActor
    private func append(_ new: [ActivityEvent]) {
        events.append(contentsOf: new)
        totalEventsObserved += new.count
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        // Keep buffer chronological. Reverse presentation handled by `displayEvents`.
    }

    /// Convenience accessor for views that want newest-first without mutating the
    /// underlying buffer.
    var displayEvents: [ActivityEvent] {
        newestFirst ? events.reversed() : events
    }
}
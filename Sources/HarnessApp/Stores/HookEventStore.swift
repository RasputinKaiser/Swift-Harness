import Foundation
import Observation

/// `@Observable` tailer for `~/.ncode/hook_events.jsonl`. Mirrors the session
/// tailer's structure: private ioQueue does reads, mutations hop to MainActor.
///
/// File is created by `scripts/hook_event_tap.py` in the harness plugin. If it
/// doesn't exist yet, the store sits idle until the file appears (dispatch source
/// on the parent directory catches creation).
@Observable
final class HookEventStore {

    var maxEvents = 2000
    private(set) var events: [HookEvent] = []
    private(set) var status: TailStatus = .idle
    /// Filter set — empty means all events.
    var eventFilter: Set<String> = []
    /// Substring to match against script name. Empty means no filter.
    var scriptFilter: String = ""

    enum TailStatus: Equatable {
        case idle
        case waiting(URL)        // file doesn't exist yet
        case tailing(URL)
        case failed(String)
    }

    init() {}

    @MainActor
    func start() {
        detach()
        let url = HarnessClient.ncodeDir.appendingPathComponent("hook_events.jsonl", conformingTo: .text)
        if FileManager.default.fileExists(atPath: url.path) {
            beginTailing(at: url)
        } else {
            status = .waiting(url)
            watchForCreation()
        }
    }

    @MainActor
    func detach() {
        directorySource?.cancel()
        directorySource = nil
        fileSource?.cancel()
        fileSource = nil
        fileHandle?.closeFile()
        fileHandle = nil
        offset = 0
    }

    var filteredEvents: [HookEvent] {
        events.filter { e in
            (eventFilter.isEmpty || eventFilter.contains(e.event))
                && (scriptFilter.isEmpty
                    || e.script.localizedCaseInsensitiveContains(scriptFilter))
        }
    }

    var outcomeCounters: [HookEvent.Outcome: Int] {
        var out: [HookEvent.Outcome: Int] = [:]
        for e in events {
            out[e.outcome, default: 0] += 1
        }
        return out
    }

    // MARK: - Internals

    private var fileHandle: FileHandle?
    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var offset: UInt64 = 0
    private let ioQueue = DispatchQueue(label: "com.rasputinkaiser.harnessapp.hook-events")

    private func watchForCreation() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            let parent = HarnessClient.ncodeDir
            let fd = open(parent.path, O_EVTONLY)
            guard fd >= 0 else { return }
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete],
                queue: self.ioQueue
            )
            src.setEventHandler { [weak self] in
                guard let self else { return }
                let url = HarnessClient.ncodeDir.appendingPathComponent("hook_events.jsonl", conformingTo: .text)
                if FileManager.default.fileExists(atPath: url.path) {
                    src.cancel()
                    Task { @MainActor in self.beginTailing(at: url) }
                }
            }
            src.setCancelHandler { close(fd) }
            src.resume()
            Task { @MainActor in self.directorySource = src }
        }
    }

    private func beginTailing(at url: URL) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            guard let fh = try? FileHandle(forReadingFrom: url) else {
                Task { @MainActor in self.status = .failed("open failed") }
                return
            }
            // Seek to end — we only want events fired after the app started watching
            let endOffset = (try? fh.seekToEnd()) ?? 0
            self.offset = endOffset
            try? fh.seek(toOffset: self.offset)

            let fd = fh.fileDescriptor
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .delete],
                queue: self.ioQueue
            )
            src.setEventHandler { [weak self] in
                guard let self else { return }
                self.drain(from: fh, url: url)
                if src.data.contains(.delete) {
                    src.cancel()
                    Task { @MainActor in
                        self.status = .waiting(url)
                        self.watchForCreation()
                    }
                }
            }
            src.setCancelHandler { fh.closeFile() }
            src.resume()

            // Drain once in case lines arrived between seekToEnd and source resume
            self.drain(from: fh, url: url)

            Task { @MainActor in
                self.fileHandle = fh
                self.fileSource = src
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

        let events = lines.compactMap { line -> HookEvent? in
            guard let d = line.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(HookEvent.self, from: d)
        }
        guard !events.isEmpty else { return }
        Task { @MainActor in self.append(events) }
    }

    @MainActor
    private func append(_ new: [HookEvent]) {
        events.append(contentsOf: new)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }
}
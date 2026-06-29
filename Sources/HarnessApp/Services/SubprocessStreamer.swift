import Foundation

/// Mutable line buffer safe to mutate from `readabilityHandler` closures.
/// Each `Pipe` gets its own instance.
private final class LineBuffer: @unchecked Sendable {
    private var data = Data()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) {
        self.onLine = onLine
    }

    func append(_ chunk: Data) {
        data.append(chunk)
        while let nl = data.firstIndex(of: 0x0A) {
            let lineData = data.subdata(in: data.startIndex..<nl)
            data.removeSubrange(data.startIndex...nl)
            if let s = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !s.isEmpty {
                onLine(s)
            }
        }
    }

    func flush() {
        if !data.isEmpty,
           let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty {
            onLine(s)
        }
        data.removeAll()
    }
}

/// Actor that spawns a `Process`, exposes an `AsyncThrowingStream<String, Error>`
/// of interleaved stdout/stderr lines, and supports cancellation via SIGTERM
/// (escalating to SIGKILL after 2s).
///
/// No polling — uses `Pipe.fileHandleForReading.readabilityHandler`. Line
/// buffering across split reads is handled by `LineBuffer`.
actor SubprocessStreamer {

    struct Result {
        let exitCode: Int
        let duration: TimeInterval
        var ok: Bool { exitCode == 0 }
    }

    private var process: Process?

    /// Spawn and stream. Cancellation via `cancel()`. The stream finishes when the
    /// process exits, throwing on launch failure but NOT on non-zero exit.
    func run(command: [String], cwd: URL?) -> AsyncThrowingStream<String, Error> {
        precondition(!command.isEmpty)
        return AsyncThrowingStream { continuation in
            Task { await self.execute(command: command, cwd: cwd, continuation: continuation) }
        }
    }

    func cancel() {
        guard let p = process else { return }
        p.terminate()
        let pid = p.processIdentifier
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            kill(pid, SIGKILL)
        }
    }

    // MARK: - Internal

    private func execute(
        command: [String],
        cwd: URL?,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: command[0])
        p.arguments = Array(command.dropFirst())
        if let cwd { p.currentDirectoryURL = cwd }

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        let start = Date()
        let outBuf = LineBuffer { continuation.yield($0) }
        let errBuf = LineBuffer { continuation.yield($0) }

        outPipe.fileHandleForReading.readabilityHandler = { [weak outBuf] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            outBuf?.append(data)
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak errBuf] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            errBuf?.append(data)
        }

        do {
            try p.run()
            process = p
            p.terminationHandler = { [weak self, weak outBuf, weak errBuf] proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                outBuf?.flush()
                errBuf?.flush()
                _ = Result(
                    exitCode: Int(proc.terminationStatus),
                    duration: Date().timeIntervalSince(start)
                )
                Task { await self?.clearProcess() }
                continuation.finish()
            }
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            continuation.finish(throwing: error)
        }
    }

    private func clearProcess() { process = nil }
}
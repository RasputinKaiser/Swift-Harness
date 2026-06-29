import Foundation

/// Unix domain socket server that receives browser commands from the
/// Python MCP bridge (`harness_browser_mcp.py`) and routes them to the
/// shared `WebViewModel` on MainActor.
///
/// Protocol: newline-delimited JSON. Each line is a `BrowserCommand`.
/// The server writes back one `BrowserReply` per command (also newline-delimited).
///
/// Socket path: `~/Library/Application Support/HarnessApp/browser.sock`
///
/// Uses raw POSIX file descriptors for predictability — NWListener/NWConnection
/// require GCD dispatch and have complex async semantics that made Phase 1
/// prove difficult with the simple stdin/stdout MCP bridge.
final class BrowserIPCServer {

    private(set) var isListening = false
    private(set) var lastError: String?
    private var serverFd: Int32 = -1
    private var acceptQueue: DispatchQueue?
    private var stopRequested = false

    /// Weak reference to the WebViewModel — set by HarnessStore.
    weak var browserModel: WebViewModel?

    var socketPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("HarnessApp", conformingTo: .directory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("browser.sock", conformingTo: .text).path
    }

    init() {}

    @MainActor
    func start() {
        guard !isListening else { return }
        stopRequested = false

        // Remove stale socket
        unlink(socketPath)

        // Create Unix domain socket
        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            lastError = "socket() failed: \(errno)"
            return
        }

        // Bind to path
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { src in
            withUnsafeMutableBytes(of: &addr.sun_path) { dest in
                let srcRaw = UnsafeRawBufferPointer(start: src, count: min(strlen(src) + 1, dest.count))
                dest.copyBytes(from: srcRaw)
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult >= 0 else {
            lastError = "bind() failed: \(errno)"
            close(serverFd)
            serverFd = -1
            return
        }

        // Listen (backlog of 5)
        guard listen(serverFd, 5) >= 0 else {
            lastError = "listen() failed: \(errno)"
            close(serverFd)
            serverFd = -1
            return
        }

        isListening = true
        AppLogger.process.info("BrowserIPCServer listening at \(self.socketPath)")

        // Accept loop on a background queue
        let q = DispatchQueue(label: "com.rasputinkaiser.harnessapp.browser-ipc-accept")
        acceptQueue = q
        q.async { [weak self] in
            self?.acceptLoop()
        }
    }

    @MainActor
    func stop() {
        stopRequested = true
        if serverFd >= 0 {
            close(serverFd)
            serverFd = -1
        }
        unlink(socketPath)
        isListening = false
    }

    // MARK: - Accept loop (runs on background queue)

    private func acceptLoop() {
        while !stopRequested {
            let clientFd = accept(serverFd, nil, nil)
            if clientFd < 0 {
                if !stopRequested {
                    AppLogger.process.error("BrowserIPC accept() failed: \(errno)")
                }
                break
            }
            handleClient(clientFd)
        }
    }

    private func handleClient(_ fd: Int32) {
        // Read one line (newline-delimited JSON)
        var buf = [UInt8]()
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == 0x0A { break }  // newline
            buf.append(byte)
        }

        guard !buf.isEmpty else {
            close(fd)
            return
        }

        let data = Data(buf)
        guard let cmd = try? JSONDecoder().decode(BrowserCommand.self, from: data) else {
            AppLogger.process.error("BrowserIPC: failed to decode command")
            close(fd)
            return
        }

        // Execute on MainActor (browserModel reads must be main-thread-safe)
        // For Phase 1, we do a blocking synchronous read — safe for get_url/get_title.
        // Phase 2+ will move to async for navigate/click/screenshot.
        let reply = executeCommandSync(cmd)

        // Send reply
        guard let replyData = try? JSONEncoder().encode(reply) else {
            close(fd)
            return
        }
        var frame = replyData
        frame.append(0x0A)  // newline delimiter
        frame.withUnsafeBytes { ptr in
            _ = write(fd, ptr.baseAddress, frame.count)
        }
        close(fd)
    }

    // MARK: - Command execution (synchronous for Phase 1)

    private func executeCommandSync(_ cmd: BrowserCommand) -> BrowserReply {
        switch cmd.tool {
        case "browser_get_url":
            let url = DispatchQueue.main.sync {
                browserModel?.url?.absoluteString ?? ""
            }
            return BrowserReply(id: cmd.id, ok: true,
                                result: AnyCodable(["url": url]), error: nil)

        case "browser_get_title":
            let title = DispatchQueue.main.sync {
                browserModel?.title ?? ""
            }
            return BrowserReply(id: cmd.id, ok: true,
                                result: AnyCodable(["title": title]), error: nil)

        default:
            return BrowserReply(id: cmd.id, ok: false, result: nil,
                                error: "unknown tool: \(cmd.tool)")
        }
    }
}
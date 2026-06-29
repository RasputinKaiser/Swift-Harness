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
        var buf = [UInt8]()
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == 0x0A { break }
            buf.append(byte)
        }
        guard !buf.isEmpty else { close(fd); return }
        guard let cmd = try? JSONDecoder().decode(BrowserCommand.self, from: Data(buf)) else {
            close(fd); return
        }
        Task { [weak self] in
            guard let self else { close(fd); return }
            let reply = await self.executeCommand(cmd)
            guard let data = try? JSONEncoder().encode(reply) else { close(fd); return }
            var frame = data; frame.append(0x0A)
            frame.withUnsafeBytes { _ = write(fd, $0.baseAddress, frame.count) }
            close(fd)
        }
    }

    @MainActor
    private func executeCommand(_ cmd: BrowserCommand) async -> BrowserReply {
        switch cmd.tool {
        case "browser_get_url":
            let url = browserModel?.url?.absoluteString ?? ""
            return BrowserReply(id: cmd.id, ok: true, result: AnyCodable(["url": url]), error: nil)
        case "browser_get_title":
            let title = browserModel?.title ?? ""
            return BrowserReply(id: cmd.id, ok: true, result: AnyCodable(["title": title]), error: nil)
        case "browser_navigate":
            let urlString = (cmd.args?["url"]?.value as? String) ?? ""
            switch BrowserGate.checkURL(urlString) {
            case .blocked(let reason):
                return BrowserReply(id: cmd.id, ok: false, result: nil, error: reason)
            case .allowed: break
            }
            if BrowserGate.isLoginOrigin(urlString) {
                AppLogger.process.warning("browser_navigate to login origin: \(urlString)")
            }
            guard let url = URL(string: urlString), let bm = browserModel else {
                return BrowserReply(id: cmd.id, ok: false, result: nil, error: "invalid URL or browser detached")
            }
            bm.isAgentDriving = true
            let nav = await bm.navigate(to: url)
            return BrowserReply(id: cmd.id, ok: nav.succeeded,
                                result: AnyCodable(["url": nav.url, "title": nav.title, "status": nav.succeeded ? "loaded" : "failed"]),
                                error: nav.error)
        case "browser_eval":
            let js = (cmd.args?["js"]?.value as? String) ?? ""
            switch BrowserGate.checkJS(js) {
            case .blocked(let reason):
                return BrowserReply(id: cmd.id, ok: false, result: nil, error: reason)
            case .allowed: break
            }
            guard let bm = browserModel else {
                return BrowserReply(id: cmd.id, ok: false, result: nil, error: "browser not attached")
            }
            let (result, error) = await bm.evalJS(js)
            return BrowserReply(id: cmd.id, ok: error == nil,
                                result: AnyCodable(["result": result ?? "null"]), error: error)
        case "browser_extract":
            let selector = (cmd.args?["selector"]?.value as? String) ?? ""
            let attr = cmd.args?["attr"]?.value as? String
            guard let bm = browserModel else {
                return BrowserReply(id: cmd.id, ok: false, result: nil, error: "browser not attached")
            }
            let (html, text, count) = await bm.extract(selector: selector, attr: attr)
            return BrowserReply(id: cmd.id, ok: true,
                                result: AnyCodable(["html": html, "text": text, "count": count]), error: nil)
        case "browser_click":
            let selector = (cmd.args?["selector"]?.value as? String) ?? ""
            guard let bm = browserModel else {
                return BrowserReply(id: cmd.id, ok: false, result: nil, error: "browser not attached")
            }
            bm.isAgentDriving = true
            let (clicked, rect, error) = await bm.click(selector: selector)
            if let rect = rect {
                AppLogger.process.info("browser_click: \(selector) at [\(rect.origin.x),\(rect.origin.y) \(rect.width)x\(rect.height)]")
                bm.addClickHighlight(rect)
            }
            return BrowserReply(id: cmd.id, ok: clicked,
                                result: AnyCodable([
                                    "matched": clicked,
                                    "clicked": clicked,
                                    "rect": rect != nil ? ["x": rect!.origin.x, "y": rect!.origin.y,
                                                           "w": rect!.width, "h": rect!.height] : nil
                                ]),
                                error: error)
        case "browser_screenshot":
            let selector = cmd.args?["selector"]?.value as? String
            let maxWidth = (cmd.args?["max_width"]?.value as? Double).map(Int.init)
            guard let bm = browserModel else {
                return BrowserReply(id: cmd.id, ok: false, result: nil, error: "browser not attached")
            }
            let shot = await bm.screenshot(selector: selector, maxWidth: maxWidth)
            return BrowserReply(id: cmd.id, ok: shot.error == nil,
                                result: AnyCodable([
                                    "path": shot.path ?? "",
                                    "width": shot.width,
                                    "height": shot.height,
                                    "b64": shot.b64 ?? "",
                                    "b64_truncated": shot.b64Truncated
                                ]),
                                error: shot.error)
        default:
            return BrowserReply(id: cmd.id, ok: false, result: nil, error: "unknown tool: \(cmd.tool)")
        }
    }
}
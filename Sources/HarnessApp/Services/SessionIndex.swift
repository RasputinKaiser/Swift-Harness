import Foundation

/// Scans ~/.ncode/sessions/*.json and returns session descriptors,
/// optionally filtering to alive PIDs.
enum SessionIndex {

    static func scan(includeDead: Bool = true) -> [SessionDescriptor] {
        let dir = HarnessClient.ncodeDir.appendingPathComponent("sessions", conformingTo: .directory)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        var out: [SessionDescriptor] = []
        for file in entries where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let desc = try? JSONDecoder().decode(SessionDescriptor.self, from: data) else {
                continue
            }
            if includeDead || desc.isAlive {
                out.append(desc)
            }
        }
        return out.sorted(by: { $0.startedAtMs > $1.startedAtMs })
    }

    /// Newest session matching cwd whose PID is still alive. Used by SessionsPane
    /// as the default selection on app launch.
    static func currentSession() -> SessionDescriptor? {
        scan(includeDead: false).first
    }
}
import Foundation
import Observation

/// Discovered NCode project (one per directory ever invoked from).
///
/// Projects live one level under ~/.ncode/projects/ as encoded path names
/// (e.g. -Users-ianzvirbulis--ncode). The original cwd is recoverable by
/// reversing the encoding: leading '-' becomes '/', subsequent '-' becomes '/'.
struct HarnessProject: Identifiable, Hashable {
    let encodedPath: String
    let decodedCwd: String

    var id: String { encodedPath }
    var displayName: String {
        // Use last path component as the short name; falls back to encoded.
        let comps = decodedCwd.split(separator: "/")
        return comps.last.map(String.init) ?? encodedPath
    }
    var projectDir: URL {
        HarnessClient.home
            .appendingPathComponent(".ncode/projects", conformingTo: .directory)
            .appendingPathComponent(encodedPath, conformingTo: .directory)
    }

    /// Decode the encoded path back to its original form.
    /// "-Users-ianzvirbulis--ncode" → "/Users/ianzvirbulis/.ncode"
    static func decode(_ encoded: String) -> String {
        guard encoded.hasPrefix("-") else { return encoded }
        return "/" + encoded.dropFirst().replacingOccurrences(of: "-", with: "/")
    }
}

/// `@Observable` registry of all NCode projects on disk and their sessions.
@Observable
final class ProjectStore {

    private(set) var projects: [HarnessProject] = []
    /// Currently expanded project encodings in the sidebar
    var expanded: Set<String> = []
    /// Selected session path (transcript URL) — drives chat detail view
    var selectedTranscriptURL: URL?
    private(set) var sessionsByProject: [String: [SessionDescriptor]] = [:]
    private(set) var lastRefresh: Date?
    private(set) var lastError: String?

    init() {}

    /// Scan ~/.ncode/projects/* for project directories.
    @MainActor
    func refresh() {
        let projectsDir = HarnessClient.home
            .appendingPathComponent(".ncode/projects", conformingTo: .directory)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]
        ) else {
            lastError = "could not read ~/.ncode/projects"
            return
        }

        var found: [(HarnessProject, Date)] = []
        for dir in entries {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            let encoded = dir.lastPathComponent
            let project = HarnessProject(encodedPath: encoded,
                                          decodedCwd: HarnessProject.decode(encoded))
            let mtime = (try? dir.resourceValues(forKeys: [.contentModificationDateKey])
                            .contentModificationDate) ?? Date.distantPast
            found.append((project, mtime))

            // Scan for sessions inside this project
            sessionsByProject[encoded] = scanSessions(in: dir)
        }
        // Most-recently-modified first
        projects = found.sorted(by: { $0.1 > $1.1 }).map { $0.0 }
        lastRefresh = Date()
        lastError = nil
    }

    /// Sessions for a project, sorted most-recently-modified first.
    func sessions(for project: HarnessProject) -> [SessionDescriptor] {
        sessionsByProject[project.encodedPath] ?? []
    }

    /// Toggle expanded state in sidebar.
    func toggle(_ project: HarnessProject) {
        if expanded.contains(project.encodedPath) {
            expanded.remove(project.encodedPath)
        } else {
            expanded.insert(project.encodedPath)
        }
    }

    /// True if the sidebar should auto-expand the most recent project on first load.
    func autoExpandFirstIfEmpty() {
        if expanded.isEmpty, let p = projects.first {
            expanded.insert(p.encodedPath)
        }
    }

    // MARK: - Internals

    private func scanSessions(in projectDir: URL) -> [SessionDescriptor] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else {
            return []
        }

        var out: [(URL, Date)] = []
        for file in entries {
            guard file.pathExtension == "jsonl",
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey])
                            .contentModificationDate) ?? Date.distantPast
            out.append((file, mtime))
        }
        return out.sorted(by: { $0.1 > $1.1 }).map { file, _ in
            // Sid is the file basename without extension
            let sid = file.deletingPathExtension().lastPathComponent
            return SessionDescriptor(
                pid: 0,  // not tracked for historical sessions
                sessionId: sid,
                cwd: HarnessProject.decode(projectDir.lastPathComponent),
                startedAtMs: 0,
                kind: "historical",
                entrypoint: "?",
                name: nil
            )
        }
    }
}
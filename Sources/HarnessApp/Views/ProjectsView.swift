import SwiftUI

/// Three-column Projects navigator + chat. Codex-style sidebar.
///
/// Left: list of project folders (one per cwd NCode has been invoked from).
/// Middle: list of sessions for the selected project (each entry is a
///         transcript file at ~/.ncode/projects/<encoded>/<sid>.jsonl).
/// Right: chat detail — when a session is selected, the chat starts a new
///         bridge in that project's cwd with a fresh session ID. If a bridge
///         is already running, it persists across project switches.
struct ProjectsView: View {
    @Environment(HarnessStore.self) private var store
    @State private var selectedProjectID: String?
    @State private var selectedSessionID: String?

    var body: some View {
        NavigationSplitView {
            projectList
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } content: {
            sessionList
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 440)
        } detail: {
            chatDetail
                .navigationSplitViewColumnWidth(min: 480, ideal: 700, max: 900)
        }
        .task {
            if store.projects.projects.isEmpty {
                store.projects.refresh()
            }
            store.projects.autoExpandFirstIfEmpty()
        }
    }

    // MARK: - Projects column

    private var projectList: some View {
        List(selection: $selectedProjectID) {
            Section {
                Button {
                    Task { await startNewChat() }
                } label: {
                    Label("New chat", systemImage: "plus.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
            Section("Projects") {
                ForEach(store.projects.projects) { project in
                    ProjectRow(project: project,
                               sessionCount: store.projects.sessions(for: project).count)
                        .tag(project.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Projects")
        .navigationSubtitle("\(store.projects.projects.count) total")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.projects.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onChange(of: selectedProjectID) { _, _ in
            selectedSessionID = nil  // clear session when project switches
        }
    }

    // MARK: - Sessions column

    @ViewBuilder
    private var sessionList: some View {
        if let pid = selectedProjectID,
           let project = store.projects.projects.first(where: { $0.id == pid }) {
            let sessions = store.projects.sessions(for: project)
            List(selection: $selectedSessionID) {
                Section("Sessions (\(sessions.count))") {
                    ForEach(sessions) { s in
                        SessionRow(session: s)
                            .tag(s.sessionId)
                    }
                }
                Section {
                    Button {
                        Task { await startNewChat(in: project) }
                    } label: {
                        Label("Start new chat…", systemImage: "plus.message")
                    }
                    if let sid = selectedSessionID,
                       let s = sessions.first(where: { $0.sessionId == sid }) {
                        Button {
                            Task { await resumeSession(s) }
                        } label: {
                            Label("Continue session in chat…", systemImage: "arrow.uturn.forward.circle")
                        }
                    }
                }
            }
            .navigationTitle(project.displayName)
            .navigationSubtitle("\(sessions.count) sessions")
        } else {
            ContentUnavailableView(
                "Select a project",
                systemImage: "folder",
                description: Text("Pick a project on the left to see its chat sessions.")
            )
        }
    }

    // MARK: - Chat detail column

    @ViewBuilder
    private var chatDetail: some View {
        if store.bridge.isRunning || store.bridge.isStarting {
            // Active chat session: split-view with companion browser
            ChatSplitView()
        } else if let sid = selectedSessionID,
                  let project = store.projects.projects.first(where: { $0.id == selectedProjectID }),
                  let s = store.projects.sessions(for: project).first(where: { $0.sessionId == sid }) {
            // Historical session picked: show transcript
            SessionTranscriptView(session: s)
        } else if selectedProjectID == nil {
            ContentUnavailableView(
                "Pick a project, or start a new chat",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Selecting a project shows its sessions here. Starting a new chat opens a fresh NCode session in that project's cwd.")
            )
        } else {
            // Project picked but no session — show a hint to start a chat
            ContentUnavailableView(
                "No session selected",
                systemImage: "plus.message",
                description: Text("Click \"Start new chat\" above to begin, or click a session in the middle column to view its transcript.")
            )
        }
    }

    // MARK: - Actions

    private func startNewChat(in project: HarnessProject? = nil) async {
        let cwd: URL
        if let p = project {
            cwd = URL(fileURLWithPath: p.decodedCwd)
        } else if let pid = selectedProjectID,
                  let p = store.projects.projects.first(where: { $0.id == pid }) {
            cwd = URL(fileURLWithPath: p.decodedCwd)
        } else {
            cwd = HarnessClient.home
        }
        if store.bridge.isRunning {
            store.bridge.stop()
        }
        await MainActor.run {
            store.bridge.start(cwd: cwd)
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        store.projects.refresh()
    }

    private func resumeSession(_ session: SessionDescriptor) async {
        let cwd = session.cwdURL ?? HarnessClient.home
        if store.bridge.isRunning {
            store.bridge.stop()
        }
        await MainActor.run {
            store.bridge.resume(session.sessionId, cwd: cwd)
        }
        // Clear transcript so the new session's events are visible
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        store.projects.refresh()
    }
}

private struct ProjectRow: View {
    let project: HarnessProject
    let sessionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(project.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(project.decodedCwd)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
            Text("\(sessionCount) session\(sessionCount == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct SessionRow: View {
    let session: SessionDescriptor

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.sessionId.prefix(8))
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                if let name = session.name {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let date = (session.startedAtMs > 0 ? session.startedAt : nil) {
                Text(date.formatted(.relative(presentation: .named)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 1)
    }
}
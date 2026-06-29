import SwiftUI

struct ContentView: View {
    @Environment(HarnessStore.self) private var store
    @State private var selection: SidebarSection? = .status
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar
        } detail: {
            detail
        }
    }

    private var sidebar: some View {
        List(SidebarSection.allCases, selection: $selection) { section in
            NavigationLink(value: section) {
                Label(section.title, systemImage: section.icon)
            }
        }
        .navigationTitle("Harness")
        .navigationSubtitle(store.statusMessage.isEmpty ? "Ready" : store.statusMessage)
        .safeAreaInset(edge: .bottom) {
            SidebarFooter()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .status: StatusPane()
        case .sessions: SessionsPane()
        case .tests: TestsPane()
        case .snapshots: SnapshotsPane()
        case .memory: MemoryPane()
        case .journal: JournalPane()
        case .hooks: HooksPlaceholder()
        case .browser: BrowserPane()
        case .none: ContentUnavailableView(
            "Select a section",
            systemImage: "sidebar.left",
            description: Text("Pick a section from the sidebar.")
        )
        }
    }
}

private struct HooksPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Hook event feed coming in Phase 3",
            systemImage: "fork.arrow.up.right.down",
            description: Text("See harness-app/PLAN.md — once `hook_event_tap.py` is added to the harness plugin, this pane will show live hook firings.")
        )
    }
}

private struct SidebarFooter: View {
    @Environment(HarnessStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "gear")
                .foregroundStyle(.secondary)
            if let s = store.testSummary {
                Text("\(s.passed) \(s.failed)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(s.allGreen ? .green : .red)
            } else {
                Text("no test data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
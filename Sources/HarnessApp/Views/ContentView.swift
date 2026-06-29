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
        case .projects: ProjectsView()
        case .agents: AgentsPane()
        case .computer: ComputerPane()
        case .cost: CostPane()
        case .automation: AutomationPane()
        case .status: StatusPane()
        case .tests: TestsPane()
        case .snapshots: SnapshotsPane()
        case .plugin: PluginPane()
        case .manifest: ManifestPane()
        case .memory: MemoryPane()
        case .journal: JournalPane()
        case .hooks: HooksPane()
        case .browser: BrowserPane()
        case .none: ContentUnavailableView(
            "Select a section",
            systemImage: "sidebar.left",
            description: Text("Pick a section from the sidebar.")
        )
        }
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
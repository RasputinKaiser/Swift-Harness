import SwiftUI

struct ContentView: View {
    @Environment(HarnessStore.self) private var store
    @State private var selection: SidebarSection? = .status
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 220
    @AppStorage("detailWidth") private var detailWidth: Double = 900

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: CGFloat(sidebarWidth), max: 320)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 620, ideal: CGFloat(detailWidth), max: 1400)
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(SidebarSection.Category.allCases) { category in
                Section(category.title) {
                    ForEach(SidebarSection.sections(in: category)) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.icon)
                        }
                    }
                }
            }
        }
        .navigationTitle("Harness")
        .navigationSubtitle(store.statusMessage.isEmpty ? "Ready" : store.statusMessage)
        .safeAreaInset(edge: .bottom) {
            SidebarFooter()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .onChange(of: selection) { _, newSection in
            if let newSection {
                store.paneUsage.track(newSection.rawValue)
            }
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
        case .skills: SkillsPane()
        case .templates: TemplatesPane()
        case .telemetry: TelemetryPane()
        case .status: StatusPane()
        case .tests: TestsPane()
        case .snapshots: SnapshotsPane()
        case .plugin: PluginPane()
        case .manifest: ManifestPane()
        case .memory: MemoryPane()
        case .journal: JournalPane()
        case .hooks: HooksPane()
        case .browser: BrowserPane()
        case .eval: EvalPane()
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
            Image(systemName: "checkmark.seal")
                .foregroundStyle(.secondary)
            if let s = store.testSummary {
                Text("\(s.passed)/\(s.total)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(s.allGreen ? .green : .orange)
            } else {
                Text("—")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

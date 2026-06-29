import Foundation

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case projects, agents, computer, cost, automation, skills, templates, telemetry, status, tests, snapshots, plugin, manifest, memory, journal, hooks, browser, eval

    var id: String { rawValue }

    /// Group panes into sections for the sidebar — reduces navigation tax
    /// by clustering related panes under a common header.
    enum Category: String, CaseIterable, Identifiable {
        case chat, dashboards, memory, plugins, advanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chat: "Chat"
            case .dashboards: "Dashboards"
            case .memory: "Memory & History"
            case .plugins: "Plugin Surfaces"
            case .advanced: "Advanced"
            }
        }
    }

    var category: Category {
        switch self {
        case .projects, .browser: .chat
        case .status, .telemetry, .cost, .tests, .journal: .dashboards
        case .memory, .snapshots, .hooks: .memory
        case .manifest, .plugin, .skills, .automation: .plugins
        case .agents, .computer, .templates, .eval: .advanced
        }
    }

    var title: String {
        switch self {
        case .projects: "Projects"
        case .agents: "Agents"
        case .computer: "Computer"
        case .cost: "Cost"
        case .automation: "Automation"
        case .skills: "Skills"
        case .templates: "Templates"
        case .telemetry: "Telemetry"
        case .status: "Status"
        case .tests: "Tests"
        case .snapshots: "Snapshots"
        case .plugin: "Plugin"
        case .manifest: "Manifest"
        case .memory: "Memory Fabric"
        case .journal: "Journal"
        case .hooks: "Hooks"
        case .browser: "Browser"
        case .eval: "Eval"
        }
    }

    var icon: String {
        switch self {
        case .projects: "folder"
        case .agents: "person.2.fill"
        case .computer: "macwindow"
        case .cost: "dollarsign.circle.fill"
        case .automation: "gearshape.2.fill"
        case .skills: "puzzlepiece.extension.fill"
        case .templates: "doc.on.clipboard.fill"
        case .telemetry: "chart.xyaxis.line"
        case .status: "speedometer"
        case .tests: "checkmark.seal"
        case .snapshots: "archivebox"
        case .plugin: "puzzlepiece.extension"
        case .manifest: "list.bullet.indent"
        case .memory: "brain.head.profile"
        case .journal: "book"
        case .hooks: "fork.arrow.up.right.down"
        case .browser: "globe"
        case .eval: "chart.bar.doc.horizontal"
        }
    }

    /// Sections in display order within each category.
    static func sections(in category: Category) -> [SidebarSection] {
        allCases.filter { $0.category == category }
    }
}
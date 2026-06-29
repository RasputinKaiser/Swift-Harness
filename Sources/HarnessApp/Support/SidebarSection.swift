import Foundation

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case projects, status, tests, snapshots, plugin, memory, journal, hooks, browser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: "Projects"
        case .status: "Status"
        case .tests: "Tests"
        case .snapshots: "Snapshots"
        case .plugin: "Plugin"
        case .memory: "Memory Fabric"
        case .journal: "Journal"
        case .hooks: "Hooks"
        case .browser: "Browser"
        }
    }

    var icon: String {
        switch self {
        case .projects: "folder"
        case .status: "speedometer"
        case .tests: "checkmark.seal"
        case .snapshots: "archivebox"
        case .plugin: "puzzlepiece.extension"
        case .memory: "brain.head.profile"
        case .journal: "book"
        case .hooks: "fork.arrow.up.right.down"
        case .browser: "globe"
        }
    }
}
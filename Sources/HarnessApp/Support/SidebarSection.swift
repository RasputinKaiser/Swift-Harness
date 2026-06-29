import Foundation

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case status, sessions, tests, snapshots, memory, journal, hooks, browser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: "Status"
        case .sessions: "Sessions"
        case .tests: "Tests"
        case .snapshots: "Snapshots"
        case .memory: "Memory Fabric"
        case .journal: "Journal"
        case .hooks: "Hooks"
        case .browser: "Browser"
        }
    }

    var icon: String {
        switch self {
        case .status: "speedometer"
        case .sessions: "antenna.radiowaves.left.and.right"
        case .tests: "checkmark.seal"
        case .snapshots: "archivebox"
        case .memory: "brain.head.profile"
        case .journal: "book"
        case .hooks: "fork.arrow.up.right.down"
        case .browser: "globe"
        }
    }
}
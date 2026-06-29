import Foundation

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case status, tests, memory, journal, browser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: "Status"
        case .tests: "Tests"
        case .memory: "Memory Fabric"
        case .journal: "Journal"
        case .browser: "Browser"
        }
    }

    var icon: String {
        switch self {
        case .status: "speedometer"
        case .tests: "checkmark.seal"
        case .memory: "brain.head.profile"
        case .journal: "book"
        case .browser: "globe"
        }
    }
}
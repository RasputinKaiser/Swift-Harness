import SwiftUI

@main
struct HarnessApp: App {
    @State private var store = HarnessStore()

    init() { AppLogger.bootstrap() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Refresh Status") { Task { await store.refreshStatus() } }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Run Tests") { Task { await store.runTests() } }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Sweep (/improve)") { Task { await store.sweep() } }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Take Snapshot…") { Task { await store.snapshot(reason: "via harness-app") } }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

private struct SettingsView: View {
    @Environment(HarnessStore.self) private var store

    var body: some View {
        Form {
            Section("Paths") {
                LabeledContent("Harness dir") {
                    Text(store.ncodeDir.path)
                        .textSelection(.enabled)
                        .font(.system(.caption, design: .monospaced))
                }
                LabeledContent("Scripts") {
                    Text(store.scriptsDir.path)
                        .textSelection(.enabled)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            Section("About") {
                LabeledContent("Version", value: Version.displayString)
                LabeledContent("Build", value: Version.build)
                LabeledContent("Author", value: "RasputinKaiser")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 480)
    }
}
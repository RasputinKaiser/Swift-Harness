import SwiftUI

@main
struct HarnessApp: App {
    @State private var store = HarnessStore()

    init() {
        AppLogger.bootstrap()
        // Start the browser IPC server so the agent can call browser_* tools
        store.browserIPC.browserModel = store.browserModel
        store.browserIPC.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 1100, minHeight: 720)
                .frame(idealWidth: 1400, idealHeight: 900)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.contentMinSize)
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
            CommandGroup(after: .toolbar) {
                Button("New Chat") {
                    if store.bridge.isRunning { store.bridge.stop() }
                    Task { await store.bridge.start(cwd: nil) }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Clear Transcript") {
                    Task { @MainActor in store.bridge.clear() }
                }
                .keyboardShortcut("k", modifiers: .command)
                Button("Stop / Interrupt") {
                    store.browserModel.isAgentDriving = false
                    Task { await store.bridge.interrupt() }
                }
                .keyboardShortcut(".", modifiers: .command)
                Button("Reload Plugin") {
                    Task {
                        await store.pluginMirror.reinstall()
                        store.manifest.refresh()
                    }
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
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
# harness-app

Native macOS SwiftUI GUI for the [harness-self-improvement](https://github.com/RasputinKaiser/harness-self-improvement) plugin. Reads harness state and drives harness scripts via subprocess, with built-in WKWebView in-app browser as a phase-2 surface.

## Status

`v0.1.0-dev` — sidebar shell with five panes (Status, Tests, Memory, Journal, Browser). Compiles and runs; iterates toward a fuller control surface over time.

## Build & run

```bash
swift build
.build/debug/HarnessApp
# or
script/build_and_run.sh
```

Requires Swift 5.9+ and macOS 14+. No Xcode project file — SwiftPM-only.

## Architecture

SwiftUI on `@Observable` (macOS 14+). Sources split by responsibility following the `swiftui-patterns` skill:

- `Sources/HarnessApp/HarnessApp.swift` — `@main App` + `SettingsView`
- `Sources/HarnessApp/Support/SidebarSection.swift` — section enum + icons
- `Sources/HarnessApp/Stores/HarnessStore.swift` — `@Observable` app store
- `Sources/HarnessApp/Services/HarnessClient.swift` — subprocess + disk read helpers, plus `MemoryFabricClient`
- `Sources/HarnessApp/Views/` — `ContentView` + five panes

### State ownership

- `HarnessStore` is `@Observable` and injected via `.environment(store)`.
- All blocking subprocess work happens on `async` tasks — UI never blocks.
- WKWebView state is wrapped in `WebViewModel` (also `@Observable`) and bridged via `NSViewRepresentable`.

## What's wired

- **Status pane** — metrics grid (Memory Fabric count, snapshot count, continuity count, test summary), latest `improvements.md` entry, action buttons (Run Tests / Sweep / Snapshot)
- **Tests pane** — Run `~/.ncode/scripts/run_tests.py`, parse pass/fail summary, monospaced output viewer with exit code + duration footer
- **Memory pane** — List of recent Memory Fabric records (filtered to `source_backed_agent_run` provenance), live filters, detail card with body + tags + provenance
- **Journal pane** — Renders `~/.ncode/improvements.md` raw, plus a "latest entry" quick card
- **Browser pane** — WKWebView with URL bar, back/forward/reload/stop, copy-current-URL, status bar showing host name

## Commands (Cmd-* shortcuts)

- **Cmd-R** — Refresh Status
- **Cmd-T** — Run Tests
- **Cmd-I** — Sweep (`/improve`)
- **Cmd-Shift-S** — Take Snapshot

## License

MIT — see LICENSE.

## Author

RasputinKaiser
# Harness App

Native macOS SwiftUI GUI for the [harness-self-improvement](https://github.com/RasputinKaiser/harness-self-improvement) plugin. Reads `.ncode` harness state, drives local harness scripts via subprocess, and provides desktop panes for chat, projects, telemetry, memory, snapshots, hooks, plugins, templates, evals, and the in-app browser.

## Status

`v0.7.0-dev` — SwiftPM macOS app with multi-pane control surfaces for observing and operating the local harness. The repository is current with `origin/main` as of 2026-06-29.

## Build & run

```bash
swift build
.build/debug/HarnessApp
# or
script/build_and_run.sh
# package a local .app bundle
script/make_app_bundle.sh
```

Requires Swift 5.9+ and macOS 14+. No Xcode project file — SwiftPM-only.

## Architecture

SwiftUI on `@Observable` (macOS 14+). Sources are split by responsibility:

- `Sources/HarnessApp/HarnessApp.swift` — `@main App` + `SettingsView`
- `Sources/HarnessApp/Support/SidebarSection.swift` — section enum + icons
- `Sources/HarnessApp/Support/Version.swift` — version/build metadata
- `Sources/HarnessApp/Stores/` — `@Observable` stores for harness, sessions, memory, snapshots, hooks, plugins, projects, evals, and pane usage
- `Sources/HarnessApp/Services/` — subprocess streaming, browser IPC, harness disk reads, voice, eval, snapshot, and session helpers
- `Sources/HarnessApp/Views/` — `ContentView` plus desktop panes for the control surface

### State ownership

- `HarnessStore` and leaf stores are `@Observable` and injected through SwiftUI environment or owned by the pane that needs them.
- All blocking subprocess work happens on `async` tasks — UI never blocks.
- WKWebView state is wrapped in `WebViewModel` (also `@Observable`) and bridged via `NSViewRepresentable`.

## What's wired

- **Status and Tests** — harness metrics, latest journal context, streaming test runs, sweep, and snapshot actions
- **Chat and Browser** — local bridge controls, transcript UI, voice input/output affordances, and WKWebView companion browsing
- **Projects and Sessions** — project discovery and live session transcript/activity surfaces
- **Memory, Snapshots, Journal, Hooks** — Memory Fabric records, snapshot catalog, improvement journal, and hook event feeds
- **Plugin, Manifest, Skills, Automation, Templates, Eval** — plugin drift/metadata surfaces plus local automation and eval controls
- **Telemetry, Cost, Computer, Agents** — usage/cost panes and machine/agent operation surfaces

## Commands (Cmd-* shortcuts)

- **Cmd-R** — Refresh Status
- **Cmd-T** — Run Tests
- **Cmd-I** — Sweep (`/improve`)
- **Cmd-Shift-S** — Take Snapshot

## License

MIT — see LICENSE.

## Author

RasputinKaiser

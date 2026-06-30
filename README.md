# Swift Harness

![Swift 5.9+](https://img.shields.io/badge/swift-5.9%2B-orange)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![Status: dev](https://img.shields.io/badge/status-dev-orange)

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/W7W7C9TC7)

Extremely Barebones, Experimental - Native macOS control surface for the [Self-Improvement-Plugin](https://github.com/RasputinKaiser/Self-Improvement-Plugin).

**Suggested GitHub topics:** `swift`, `swiftui`, `macos`, `ai-agents`, `agent-harness`, `ncode`, `developer-tools`, `automation`, `evals`, `memory-fabric`

Swift Harness is a SwiftUI desktop app for running, watching, and operating a local NCode self-improvement harness. It reads `.ncode` state from disk, drives harness scripts through subprocess calls, streams NCode chat sessions, shows Memory Fabric records, tracks hook events, manages snapshots, exposes plugin surfaces, and provides a built-in browser that agents can drive through a local IPC bridge.

It is meant for long agent workflows where a terminal alone starts to fall apart.

## What this is

Swift Harness is a local macOS app for working with an NCode harness from a GUI.

It gives you panes for:

- live harness status
- test runs
- self-correction sweeps
- snapshots
- projects
- sessions
- Memory Fabric records
- hook events
- plugin drift
- manifest inspection
- prompt templates
- eval cases
- cost and token usage
- telemetry
- browser control
- agent activity
- local computer state

The app does not replace NCode. It sits beside it and gives the harness a desktop control panel.

## Public status

This project is public-readable documentation for a local-first macOS harness app. It assumes a working NCode setup, the companion Self-Improvement-Plugin, and local harness state under `~/.ncode`.

The repo is useful if you are exploring:

- native SwiftUI control surfaces for AI agents
- local agent harness dashboards
- Memory Fabric browsers
- agent test and eval UIs
- subprocess-driven chat bridges
- browser IPC for local agents

Expect sharp edges. This is an active development app, not a notarized public release.

## Current status

`v0.7.0-dev`

This is a SwiftPM macOS app with multi-pane surfaces for observing and operating the local harness. It is built around the Self-Improvement-Plugin workflow and assumes the harness scripts live under `~/.ncode`.

## Requirements

| Requirement | Notes |
|---|---|
| macOS 14+ | The app uses SwiftUI `@Observable`, so macOS 14 is the floor. |
| Swift 5.9+ | Required by `Package.swift`. |
| NCode | Used by the chat bridge. The app looks for `~/.local/bin/ncode`, then `/usr/local/bin/ncode`. |
| Self-Improvement-Plugin | The app is designed around that plugin’s scripts, memory, hooks, snapshots, and eval surfaces. |
| Python 3 | Required for local harness scripts such as `run_tests.py`, `self_correct.py`, and `snapshot_harness.py`. |

There is no Xcode project file. This repo is SwiftPM-only.

## Build and run

Build with SwiftPM:

```bash
swift build
```

Run the debug binary:

```bash
.build/debug/HarnessApp
```

Or use the helper script:

```bash
script/build_and_run.sh
```

That script builds the app with SwiftPM and launches the debug executable.

## Build a local `.app` bundle

Create a local app bundle:

```bash
script/make_app_bundle.sh
```

Create a release bundle:

```bash
script/make_app_bundle.sh --release
```

The bundle script writes the app to:

```text
~/Applications/harness-app/HarnessApp.app
```

By default, it uses ad-hoc signing. To sign with a specific identity, set:

```bash
export HARNESS_APP_IDENTITY="Developer ID Application: Your Name"
script/make_app_bundle.sh --release
```

If macOS blocks the app because of Gatekeeper, right-click the app and choose **Open**.

## Demo video

A local demo video lives here:

```text
docs/video/swift-harness-launch/renders/swift-harness-launch.mp4
```

The source composition lives in:

```text
docs/video/swift-harness-launch/
```

The video uses real Harness App screenshots across Status, Plugin Drift, Memory Fabric, Eval, and Agents panes, plus cards for each Self-Improvement-Plugin slash command.

## What it can do

### Operate the harness

Swift Harness can run common harness actions from the desktop:

| Action | Backing script or surface |
|---|---|
| Refresh status | Reads local harness state from `~/.ncode`. |
| Run tests | `~/.ncode/scripts/run_tests.py` |
| Run self-correction sweep | `~/.ncode/scripts/self_correct.py` |
| Take snapshot | `~/.ncode/scripts/snapshot_harness.py` |
| Inspect latest improvement | `~/.ncode/improvements.md` |
| Count snapshots | `~/.ncode/backups/snapshots` |
| Count continuity packets | `~/.ncode/continuity` |

### Run chat sessions

The app includes a bidirectional NCode subprocess bridge.

It starts NCode in stream JSON mode:

```text
ncode --print \
  --input-format stream-json \
  --output-format stream-json \
  --include-partial-messages \
  --session-id <uuid> \
  --permission-mode bypassPermissions
```

The bridge writes user messages to stdin as JSON and reads assistant, tool, result, and system events from stdout.

The chat bridge tracks:

- session ID
- working directory
- resume state
- assistant events
- tool use blocks
- tool result blocks
- result events
- input tokens
- output tokens
- total cost
- stop reason
- pending turns
- latest assistant text
- plan proposals

### Resume sessions

The bridge can fork-continue an existing NCode session through `--resume`.

That lets you continue work from a prior session ID without making the parent UI state messy.

### Use plan mode

The chat bridge supports plan mode.

When plan mode is enabled, the bridge starts NCode with:

```text
--permission-mode plan
```

If the assistant emits an `ExitPlanMode` tool call, Swift Harness extracts the proposed plan and presents it as a pending approval flow.

### Interrupt work

You can interrupt the current NCode turn from the app. The bridge terminates the subprocess and keeps any partial output already shown in the transcript.

## Sidebar layout

Swift Harness groups panes into five sidebar sections.

| Group | Panes |
|---|---|
| Chat | Projects, Browser |
| Dashboards | Status, Telemetry, Cost, Tests, Journal |
| Memory & History | Memory Fabric, Snapshots, Hooks |
| Plugin Surfaces | Manifest, Plugin, Skills, Automation |
| Advanced | Agents, Computer, Templates, Eval |

## Pane guide

### Projects

Project discovery and session-oriented project navigation.

Use this when you want to start from a repo, inspect known projects, or work with a local task scope.

### Browser

Built-in WKWebView companion browser.

The browser can be used by the user directly, and it can also receive local agent commands through the browser IPC bridge.

### Status

Main harness dashboard.

Shows current harness state, latest improvement context, snapshot count, continuity packet count, and status messages from recent actions.

### Tests

Test runner pane for the local harness regression suite.

This pane runs:

```bash
python3 ~/.ncode/scripts/run_tests.py
```

The app parses output in this format:

```text
results: <pass> pass, <fail> fail
```

and displays pass/fail status in the UI.

### Telemetry

Usage and activity dashboard for local harness work.

Useful for seeing how the app and harness are being used across sessions.

### Cost

Cost and token tracking for NCode chat sessions.

The bridge records result events and tracks input tokens, output tokens, turn duration, stop reason, and total cost.

### Journal

Improvement and session history surface.

Useful for seeing what the harness recorded after prior work.

### Memory Fabric

Memory explorer for local Memory Fabric records.

Swift Harness can query recent source-backed agent run records and show scoped lessons, outcomes, and memory metadata.

### Snapshots

Snapshot catalog for local harness backups.

The app can call the snapshot script and read from:

```text
~/.ncode/backups/snapshots
```

### Hooks

Hook event feed.

This pane surfaces hook activity without forcing you to dig through JSONL logs by hand.

### Plugin

Plugin mirror and drift surface.

Useful for checking whether the local plugin install matches expected files and metadata.

### Manifest

Hooks, agents, commands, and plugin manifest inspection.

Use this when you want to see what the harness thinks is installed and wired.

### Skills

Skill/plugin surface for local harness capability tracking.

### Automation

Local automation controls and status.

### Agents

Subagent run catalog.

Useful for inspecting delegation runs, fan-out work, and bounded agent activity.

### Computer

Machine and local operation surface.

### Templates

Prompt template library.

Useful for reusable local prompts and harness workflows.

### Eval

Evaluation harness UI.

The app includes stores and runner support for eval cases, grading, and local agent quality measurement.

## Browser IPC

Swift Harness starts a local Unix domain socket server at:

```text
~/Library/Application Support/HarnessApp/browser.sock
```

The Python MCP bridge can send newline-delimited JSON commands to that socket. Swift Harness routes those commands to the shared browser model on the main actor and returns newline-delimited JSON replies.

Supported browser tools include:

| Tool | Purpose |
|---|---|
| `browser_get_url` | Return the current browser URL. |
| `browser_get_title` | Return the current page title. |
| `browser_navigate` | Navigate the browser to a URL. |
| `browser_eval` | Run JavaScript in the browser after gate checks. |
| `browser_extract` | Extract text, HTML, or attributes from a selector. |
| `browser_click` | Click a selector and highlight the clicked rect. |
| `browser_screenshot` | Capture a page or selector screenshot. |

The browser bridge includes URL and JavaScript gate checks before navigation or script execution.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Cmd-R` | Refresh Status |
| `Cmd-T` | Run Tests |
| `Cmd-I` | Sweep through `/improve` |
| `Cmd-Shift-S` | Take Snapshot |
| `Cmd-Shift-N` | New Chat |
| `Cmd-K` | Clear Transcript |
| `Cmd-.` | Stop / Interrupt |
| `Cmd-Shift-L` | Reload Plugin |

## Architecture

Swift Harness uses SwiftUI and Observation.

The app entry point owns a single `HarnessStore` and injects it into the SwiftUI environment. Panes either use that shared store or own smaller leaf stores for their own state.

```text
Sources/HarnessApp/
├── HarnessApp.swift
├── Support/
├── Stores/
├── Services/
└── Views/
```

### App entry

| File | Purpose |
|---|---|
| `Sources/HarnessApp/HarnessApp.swift` | `@main` app, app commands, settings window, browser IPC startup. |
| `Sources/HarnessApp/Support/Version.swift` | Single source of truth for version/build metadata. |
| `Sources/HarnessApp/Support/SidebarSection.swift` | Sidebar sections, titles, icons, and groupings. |

### Stores

`HarnessStore` is the top-level state container.

It owns or exposes stores for:

| Store | Purpose |
|---|---|
| `SessionActivityStore` | Live session tailing for session panes. |
| `SnapshotStore` | Snapshot catalog. |
| `HookEventStore` | Hook event feed. |
| `PluginMirrorStore` | Plugin drift and reinstall surface. |
| `MemoryStore` | Memory Fabric explorer. |
| `NCodeBridge` | Bidirectional NCode subprocess chat bridge. |
| `ProjectStore` | Project navigator. |
| `ManifestStore` | Hooks, agents, and commands catalog. |
| `SubagentStore` | Subagent run catalog. |
| `PromptTemplateStore` | Prompt template library. |
| `VoiceInputManager` | Hold-to-talk dictation support. |
| `VoiceOutputManager` | Assistant response speech through `AVSpeechSynthesizer`. |
| `WebViewModel` | Shared WKWebView model. |
| `BrowserIPCServer` | Browser command socket server. |
| `EvalCaseStore` | Eval case store. |
| `EvalRunner` | Eval runner. |
| `PaneUsageTracker` | Pane usage telemetry. |

### Services

Services handle local work outside SwiftUI views.

| Service | Purpose |
|---|---|
| `HarnessClient` | Runs local subprocesses and reads harness state from disk. |
| `NCodeBridge` | Starts and manages NCode chat sessions through stream JSON. |
| `BrowserIPCServer` | Accepts browser commands over a local Unix socket. |
| Browser services | Wrap WKWebView navigation, extraction, clicking, screenshots, and JavaScript eval. |
| Eval services | Run and grade eval cases. |
| Snapshot/session services | Read local harness history and backup state. |
| Voice services | Handle dictation and spoken assistant output. |

### Views

Views are organized by pane.

`ContentView` uses `NavigationSplitView` with the sidebar on the left and the selected pane on the right.

The app window defaults to:

```text
1280 × 820
```

with a minimum content size of:

```text
1080 × 680
```

## Local paths

Swift Harness assumes these local paths:

| Path | Purpose |
|---|---|
| `~/.ncode` | Main harness directory. |
| `~/.ncode/scripts` | Harness scripts. |
| `~/.ncode/improvements.md` | Latest self-correction entries. |
| `~/.ncode/backups/snapshots` | Harness snapshots. |
| `~/.ncode/continuity` | Continuity packets. |
| `~/.codex/plugins/cache/ralto-local/codex-memory-fabric` | Memory Fabric plugin cache lookup path. |
| `~/Library/Application Support/HarnessApp/browser.sock` | Browser IPC socket. |
| `~/.ncode/usage-data/pane-usage.json` | Pane usage telemetry. |

## Common workflows

### Start the app and run a status check

```bash
script/build_and_run.sh
```

Then press:

```text
Cmd-R
```

### Run the harness test suite

Press:

```text
Cmd-T
```

or use the Tests pane.

### Run a self-correction sweep

Press:

```text
Cmd-I
```

This calls the same improvement flow as `/improve`.

### Take a snapshot before risky work

Press:

```text
Cmd-Shift-S
```

The app calls:

```bash
python3 ~/.ncode/scripts/snapshot_harness.py --reason "via harness-app"
```

### Start a new chat session

Press:

```text
Cmd-Shift-N
```

The app starts a new NCode subprocess and streams events into the Chat UI.

### Interrupt the current agent turn

Press:

```text
Cmd-.
```

The app terminates the active NCode subprocess and keeps visible partial output.

### Reload plugin state

Press:

```text
Cmd-Shift-L
```

The app reinstalls through the plugin mirror surface and refreshes manifest state.

## Troubleshooting

### `ncode binary not found`

Swift Harness checks:

```text
~/.local/bin/ncode
/usr/local/bin/ncode
```

Make sure one of those paths exists and is executable.

### Tests do not run

Make sure this script exists:

```text
~/.ncode/scripts/run_tests.py
```

Then try:

```bash
python3 ~/.ncode/scripts/run_tests.py
```

from the terminal.

### Snapshot fails

Make sure this script exists:

```text
~/.ncode/scripts/snapshot_harness.py
```

Also check that the app can write to:

```text
~/.ncode/backups/snapshots
```

### Memory Fabric records are empty

Make sure the Memory Fabric plugin is installed and that the cache path exists under:

```text
~/.codex/plugins/cache/ralto-local/codex-memory-fabric
```

Swift Harness looks for a cached `memory_fabric.py` script inside the plugin cache.

### Browser IPC is not responding

Check that the app is open and that this socket exists:

```text
~/Library/Application Support/HarnessApp/browser.sock
```

If the socket is stale, quit and reopen Swift Harness.

### The app opens but panes look empty

Most panes read local `.ncode` state. If the harness has not generated snapshots, continuity packets, hook events, memory records, eval cases, or journal entries yet, those panes may have little to show.

## Development notes

- The app keeps blocking subprocess work off the UI thread.
- `HarnessClient` uses async subprocess calls for Python harness scripts.
- `NCodeBridge` caps chat events by default to avoid unbounded memory growth in long sessions.
- Cost and token totals are tracked incrementally to avoid repeated full transcript scans.
- Hook noise is filtered so `hook_started` and `hook_response` events do not bury useful transcript signal.
- Browser IPC uses POSIX Unix sockets instead of `NWListener` for simpler stdin/stdout MCP bridge behavior.
- Pane usage is tracked so the app can show which surfaces are actually used over time.

## Repo layout

```text
.
├── Package.swift
├── README.md
├── Sources/
│   └── HarnessApp/
│       ├── HarnessApp.swift
│       ├── Support/
│       ├── Stores/
│       ├── Services/
│       └── Views/
├── docs/
│   └── video/
│       └── swift-harness-launch/
└── script/
    ├── build_and_run.sh
    └── make_app_bundle.sh
```

## Security

Swift Harness runs local subprocesses, reads local harness state, and opens a local browser IPC socket. Review the code before using it in another environment.

Do not paste secrets, local transcripts, tokens, private repo content, or screenshots with private data into public issues. See `SECURITY.md` for vulnerability reporting notes.

## Contributing

Contributions are welcome through issues and pull requests. See `CONTRIBUTING.md` before opening larger changes.

## License

MIT. See `LICENSE`.

## Author

RasputinKaiser

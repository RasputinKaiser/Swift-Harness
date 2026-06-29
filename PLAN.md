# Harness App — v1.0 Implementation Plan

Phased plan to evolve `harness-app` from v0.1.0-dev into a production-quality native macOS app that ties the NCode harness into genuine utility. Each phase ships something runnable; no phase leaves the app broken.

Based on actual repo state (verified, not assumed):
- `~/Code/harness-app/` SwiftPM project, 7 source files, builds in 2.4s
- 28 scripts at the Self-Improvement-Plugin checkout's `scripts/` directory
- Live data: `~/.ncode/{improvements.md,backups/snapshots/,continuity/,sessions/*.json}`
- Sessions transcript: `~/.ncode/projects/<encoded-cwd>/<sessionId>.jsonl` (per-line: `assistant`/`user`/`file-history-snapshot` entries)
- Codex.app at `/Applications/Codex.app` is Electron (opaque JS, no source available to cite); patterns below grounded in well-known SwiftUI idioms

---

## Phase 1 — Live Session Activity Stream

**Goal:** Show what the agent is doing right now without taking over the running terminal.

**Deliverables**
- `Sources/HarnessApp/Models/SessionActivityEvents.swift` — value types: `ToolCall` (name, parsed input, toolUseId, startedAt, status), `AssistantText`, `UserTurn`, `FileHistorySnapshotEntry`, all parsed from one line of project transcript JSONL
- `Sources/HarnessApp/Services/SessionIndex.swift` — scans `~/.ncode/sessions/*.json`, returns `[SessionDescriptor]` (pid, sessionId, cwd, startedAt, entrypoint); exposes `currentSession` (newest pid still running via `kill(pid, 0)`)
- `Sources/HarnessApp/Services/SessionTailer.swift` — opens transcript file with `FileHandle` + `DispatchSource.makeFileSystemObjectSource` on the directory; per-line `AsyncStream` surfaces new entries. 250ms backoff on file-source notifications
- `Sources/HarnessApp/Stores/SessionActivityStore.swift` — `@Observable`, owns `[ActivityEvent]` capped at last 500, exposes `attach(session:)` / `detach()`
- `Sources/HarnessApp/Views/SessionsPane.swift` — top: 1-line session picker (pid + cwd + "live" dot); bottom: scrolling `List` of activity events (`AssistantText` rows monospaced; `ToolCall` rows render name + parsed input + status chip)
- Insert `.sessions` between `.status` and `.tests` in `SidebarSection`
- Update `HarnessStore` to hold a `liveSession: SessionActivityStore` reference

**UX:** `List` with `.listStyle(.inset)` + `ScrollViewReader.scrollTo(id)` to auto-stick to bottom (mirrors Codex App transcript view). Status chip is a `Capsule` tinted by outcome.

**Tests:** SwiftPM test target `HarnessAppTests` with `SessionActivityEventsTests` parsing 5 fixture lines captured from a real transcript (redact cwd). `harness-app/self_check` regression case in `run_tests.py` runs `swift build` + tests.

**Risk + rollback:** Tailer may leak file handles. Gate behind `do/catch` with `defer close()`. Roll back by deleting `SessionsPane.swift` + model file; app compiles without them.

## Phase 2 — Snapshot Catalog & Rollback

**Goal:** List every script snapshot, view manifest, one-click restore with pre-restore safety backup.

**Deliverables**
- `Sources/HarnessApp/Services/SnapshotStore.swift` — `@Observable`, queries `HarnessClient.snapshotsDir`, caches `[Snapshot]`, refreshes via `DispatchSource`
- `Sources/HarnessApp/Models/Snapshot.swift` — decodes `manifest.json` into value struct with `hash`, `createdAt`, `reason`, `files: [SnapshotFile(name, sha256)]`
- `Sources/HarnessApp/Views/SnapshotsPane.swift` — left: `List` of snapshots sorted newest-first with hash, reason, age, file-count; right: detail panel listing files + per-file sha256 + "Diff vs live" comparison (chip red if drifted)
- Toolbar: "Restore…" → confirmation sheet runs `restore_harness.py <hash>` via streaming subprocess
- `Sources/HarnessApp/Services/HarnessClient+Snapshots.swift` extension: `listSnapshots() -> [Snapshot]`, `diffSnapshot(_:) -> [SnapshotFileDiff]`

**UX:** Master-detail `NavigationSplitView` two-column with `.detail` only showing for selection; toolbar primary action with sheet confirmation (mirrors Codex App plugin-manager reinstall flow).

**Tests:** `SnapshotDecodeTests` with the two real manifests in `~/.ncode/backups/snapshots/`. `run_tests.py` regression `test_snapshot_manifest_decode`.

**Risk + rollback:** Restore is destructive. Always pre-restore-auto-snapshot via `snapshot_harness.py --reason "before restore to <hash>"` inside the action. If restore fails mid-way, surface stderr verbatim; user runs `restore_harness.py <pre-restore-hash>` manually.

## Phase 3 — Hook Event Feed

**Goal:** Surface every hook firing with outcome, script, event, matcher, additionalContext injected.

**Deliverables**
- `Sources/HarnessApp/Services/HookEventStore.swift` — `@Observable`, holds `[HookEvent]` capped at 2000, subscribes to new file `~/.ncode/hook_events.jsonl` via `DispatchSource`
- `Sources/HarnessApp/Models/HookEvent.swift` — `{ id, ts, event, matcher?, script, exitCode, durationMs, outcome: "fire"|"skip"|"block"|"feedback", additionalContextPreview?, stderrPreview? }`
- `Sources/HarnessApp/Views/HooksPane.swift` — filter chips for `PreToolUse`/`PostToolUse`/etc., search field for scriptSubstring, list of rows with outcome chip + duration + script name, expandable `DisclosureGroup` showing additionalContext JSON
- Update `SidebarSection` to add `.hooks` after `.journal`

**New harness-side script:** `scripts/hook_event_tap.py` — wrapper invoked as `python3 hook_event_tap.py <event> <script> "<cmd>"` that runs the wrapped command, captures stdout/stderr/exit/duration, appends one JSON line to `~/.ncode/hook_events.jsonl`. Update `hooks/hooks.json` to wrap each existing hook in this tap (preserves `additionalContext` and `statusMessage` semantics). Honour opt-out env var `HARNESS_APP_NO_TAP=1`.

**UX:** Filter chip row like Codex App plugin filter; outcome chip red for "block", amber for "feedback", green for "fire", gray for "skip".

**Tests:** `HookEventDecodeTests`. Extend `run_tests.py` with test that runs the tap once and asserts a JSON line lands in `~/.ncode/hook_events.jsonl`. Assert `memory_fabric.py hook-health` reports non-zero count.

**Risk + rollback:** Tap adds one process fork per hook fire; with ~10 hooks per turn this is a real pessimization. Mitigate: only wrap PostToolUse hooks in Phase 3 (highest signal). Roll back: revert `hooks.json`, delete pane.

## Phase 4 — Plugin Marketplace Mirror (Drift Detection)

**Goal:** Detect when installed harness (`~/.ncode/scripts/`) drifts from the Self-Improvement-Plugin source repo, prompt reinstall.

**Deliverables**
- `Sources/HarnessApp/Services/PluginMirrorStore.swift` — `@Observable`, computes hash-by-hash drift against the Self-Improvement-Plugin `scripts/*.py` files and `hooks/hooks.json`, plus live snapshot at install time tracked via `~/.ncode/.harness.installed.json`
- `Sources/HarnessApp/Views/PluginPane.swift` — top: installed vs source per-file drift chips. "Drift detected" banner when any sha256 diverges. Toolbar: "View diff" (opens offending file in `WebView` showing `file:///` diff via tiny HTML template), "Reinstall…" (confirmation sheet runs new `install.sh`)
- Update `SidebarSection` to add `.plugin` before `.browser`

**New harness-side artifacts:** `install.sh` at the Self-Improvement-Plugin root that copies scripts to `~/.ncode/scripts/`, merges `hooks/hooks.json` into `~/.ncode/settings.local.json`, overwrites `~/.ncode/.harness.installed.json` with `{commit, ts, files:{name:sha256}}`. None exists yet.

**UX:** Drift banner mirrors Codex App plugin-update toast. Confirmation sheet mirrors its reinstall dialog. Diff preview reuses `WKWebView` from `BrowserPane`.

**Tests:** `DriftDetectionTests`. Extend `run_tests.py` with `test_install_sh_idempotent` (runs install.sh twice, asserts no file changes second time). Extend `validate_harness.py` to check `.harness.installed.json` exists and resolved commit is in `git log`.

**Risk + rollback:** Bad `install.sh` could clobber user-edited scripts. Mitigate: `install.sh` calls `snapshot_harness.py --reason "pre-install"` first (lands in Phase 2 catalog and is rollback-able). Roll back pane: delete `PluginPane.swift`; GUI compiles fine.

## Phase 5 — Script Runner with Live Output Stream + Cancellation

**Goal:** Authentic-free picker for any of the 28 scripts under `~/.ncode/scripts/`, with live stdout/stderr and Cancel button.

**Deliverables**
- `Sources/HarnessApp/Services/SubprocessStreamer.swift` — replaces block-until-exit path with a new `actor`: spawns `Process`, exposes `AsyncThrowingStream<String, Error>` for stdout+stderr line interleave, plus `cancel()` that sends `SIGTERM` then `SIGKILL` after 2s. Uses `Pipe` + `fileHandleForReading.readabilityHandler` (no polling)
- `Sources/HarnessApp/Stores/ScriptRunnerStore.swift` — `@Observable`, registry of scripts discovered by scanning `~/.ncode/scripts/*.py` (name, mtime, size), plus currently-running script: `currentScript: String?`, `stdoutLines: [String]`, `stderrLines: [String]`, `isRunning`, `startedAt`
- `Sources/HarnessApp/Views/ScriptsPane.swift` — left: searchable `List` of scripts (group by tested-vs-untested using `run_tests.py` coverage list parsed from improvements.md). Right: live console `ScrollView` of `Text` rows, color-coded stdout/stderr
- Rewrite `HarnessStore.runTests()` to delegate to new streamer
- Snapshot restore in Phase 2 now uses the streamer

**UX:** Console row like Xcode's console with red tint for stderr. Cancel button uses `.buttonStyle(.bordered)` with `.keyboardShortcut(.escape, modifiers: .command)`.

**Tests:** `SubprocessStreamerTests` that runs `/bin/echo` with interleaved `sleep` lines, asserts ordering. Extend `run_tests.py` with `test_script_smoke_list_json_shape` asserting `script_smoke.py --list` returns expected schema.

**Risk + rollback:** `readabilityHandler` blocks must be torn down explicitly or pipes leak. Wrap in `defer { pipe.fileHandleForReading.readabilityHandler = nil }`. Roll back: revert `runTests()` to old path; delete `ScriptsPane.swift`.

## Phase 6 — Memory Fabric Explorer (Search + Decay Sort + Archive)

**Goal:** Replace stub Memory pane with full Memory Fabric explorer — search, filter, decay-sort, provenance chain, mark-for-archive.

**Deliverables**
- `Sources/HarnessApp/Services/MemoryStore.swift` — `@Observable`. Calls `memory_fabric.py search --json` with current query/filter; caches results. Calls `memory_fabric.py thread-brief --record <id>` for selected record to surface provenance
- `Sources/HarnessApp/Models/MemoryRecord.swift` — promoted to full value type (id, tier, title, body, tags, confidence, createdAt, sourceRefs: [MemorySourceRef])
- Rewritten `Sources/HarnessApp/Views/MemoryPane.swift` — toolbar with query field, tier filter (`learning`/`work`/`knowledge`), sort menu (recent: decay, confidence, version asc/desc), "Show archived" toggle (off by default). Records show decay score if reported. Mark-as-archive writes JSONL line to `~/.ncode/memory_archive.jsonl` (new side log only the app reads; `harness_gc.py` can later consume)
- Update `HarnessStore.recentRecords` → migrate to `memoryStore.records`

**UX:** Master-detail with `DisclosureGroup` for source refs. Decay score shown as small horizontal bar.

**Tests:** `MemoryRecordDecodeTests` with synthetic fixture. Extend `run_tests.py` to assert `memory_fabric_search_round_trip`.

**Risk + rollback:** Writing to `memory_archive.jsonl` is only new mutation; on rollback app just stops writing, existing records stay.

## Phase 7 — Real `.app` Bundle, Async Subprocess Throughout, Light Telemetry

**Goal:** Ship harness-app as a signed `.app` bundle that launches from Finder, restores prior window state, logs enough to debug field issues.

**Deliverables**
- `script/make_app_bundle.sh` — wraps `swift build -c release`, copies `.build/release/HarnessApp` into `HarnessApp.app/Contents/MacOS/`, writes minimal `Info.plist` with `CFBundleIdentifier=com.rasputinkaiser.harnessapp`, `LSMinimumSystemVersion=14.0`, `NSHighResolutionCapable=true`. Optional codesign with ad-hoc Developer ID identity if `HARNESS_APP_IDENTITY` set
- `Sources/HarnessApp/Support/AppLogger.swift` — tiny `os.Logger` wrapper (`os_log` subsystem `com.rasputinkaiser.harnessapp`) used by SubprocessStreamer, SessionTailer, HookEventStore
- Migrate `HarnessStore` to one `@Observable` `AppStore` plus per-pane stores (`SessionsActivityStore`, `SnapshotStore`, `HookEventStore`, `MemoryStore`, `ScriptRunnerStore`, `PluginMirrorStore`) — stores become leaf `@Observable`s, injected via `.environment`
- Document Full Disk Access requirements in README
- `Sources/HarnessApp/Support/Version.swift` — single source of truth for `appVersion`, `appBuild`

**UX:** `WindowGroup` per-state restoration via `.windowToolbarStyle(.unified)` and `NavigationSplitView.columnVisibility` binding (already partly wired). Telemetry via `os.Logger`.

**Tests:** `script/ci_smoke.sh` invoking `script/make_app_bundle.sh`, then `open` the bundle, then `pkill HarnessApp` after 5s — assert exit 0. Extend `run_tests.py` with `test_app_bundle_smoke`.

**Risk + rollback:** Signing failures are the common case — make `codesign` optional; the bundle works ad-hoc. Roll back: revert to `swift run HarnessApp` launch path.

---

## Architecture

### IPC vs. file polling

Three channels by latency:
1. **Low-frequency state** (snapshot list, plugin drift, memory record counts): `DispatchSource.makeFileSystemObjectSource` on the containing directory
2. **High-frequency stream** (session transcript, hook event log): `FileHandle` with `readabilityHandler` — no polling, no CPU cost when idle
3. **Per-script invocation** (Phase 3's tap): writes JSONL side log the app tails

No Unix domain socket, no XPC, no Rust — pure Swift, no dependencies.

### Permissions model

Hardcoding `~/.ncode` and `~/Code/...` paths means **no App Sandbox**. Document this in README. Ship with Hardened Runtime. Request Full Disk Access via one-time prompt that deep-links to `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`. Settings pane surfaces current authorization state.

### State management

Keep `@Observable`; do NOT add Combine — Observation already gives diffing and avoidable recomputation. Single `HarnessStore` becomes thread-unsafe once Phase 1 starts streaming from background queues — split per pane so reads happen on `@MainActor` and writes from `DispatchSource` callbacks go through `Task { @MainActor in self.x = ... }`.

### Build / distribution

SwiftPM-only `Package.swift` stays. Phase 7 `.app` bundle produced by `script/make_app_bundle.sh` copying release binary into `.app` skeleton. Codesigning optional (ad-hoc works locally). Notarization deferred until a public release is on the table. Single-tenant — no Sparkle, no auto-update.

---

## Defer Indefinitely

- Themes, dashboard customization, menu-bar extra, iOS port, widget, system tray — vanity, no harness utility
- Making the app able to *run* slash commands itself — CLI already owns this UX; duplicating invokes creates a second, worse terminal
- Re-implementing /improve, /verify, /checkpoint inside the app shell — they live in `commands/*.md`; invoking via subprocess (already done) is the right boundary
- MCP server browser (mirroring Codex App MCP browser) — Ralts-side MCP is rich but adds nothing while sat at the terminal
- Plan-approval UI / agent dispatch view (Claude Code Noumena fork internals) — defer until Phase 3's Hook Event Feed proves people use the activity surface while not in terminal
- Worktree support — Harness doesn't use worktrees today
- Cloud sync of Memory Fabric or snapshots — out of scope; network calls explicitly excluded
- Tray-style notifier that fires on every hook — spam; defer until HookEventStore filters mature and "notify on block" rule can gate it
- Custom themed transcript renderer with syntax highlighting — Phase 1's `List` of typed rows is enough

---

## Next 3 highest-leverage changes to ship first

1. **Phase 5 `SubprocessStreamer.swift` first.** Foundational dependency for Phase 1's session tailer (same `FileHandle.readabilityHandler` pattern) and Phase 2's restore action. Unblocks removing block-on-`waitUntilExit` path that currently locks UI. Ship before any new feature.
2. **`Helpers/HarnessClient+LiveSessions.swift` + `SessionsPane.swift` (Phase 1 cut down).** Single highest-utility thing the app can do: let RasputinKaiser watch a harness run while keeping the terminal clean. Minimum: list sessions from `~/.ncode/sessions/*.json`, tail project transcript JSONL, render typed rows. Defer filter UI to follow-up.
3. **`SnapshotStore` + `SnapshotsPane.swift` (Phase 2).** Smallest blast radius, immediately useful, exercises new streamer, proves `.app` can mutate disk via harness scripts with pre-restore safety already provided by `restore_harness.py`. Pairs naturally with Phase 1's diff-in-transcript awareness.

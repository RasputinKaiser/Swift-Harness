# Harness App UI/UX Improvement Plan

Date: 2026-06-29

## Evidence Boundary

This plan is based on the real SwiftPM source checkout at `/Users/ianzvirbulis/Code/harness-app`, the packaged app at `/Users/ianzvirbulis/Applications/harness-app/HarnessApp.app`, and live Computer Use inspection of bundle id `com.rasputinkaiser.harnessapp`.

The original source is not in `.ncode`. `.ncode` is the runtime data/control surface that Harness App reads and mutates: scripts, sessions, snapshots, hook events, usage data, eval cases, memory archive state, and plugin install cache.

## What Already Exists

- Native SwiftUI macOS app with split source structure under `Sources/HarnessApp`.
- `ContentView` uses `NavigationSplitView` with grouped sidebar categories.
- Existing shared UI primitives: `PaneHeader`, `PaneScaffold`, `DensePaneScaffold`, `FullWidthPaneScaffold`, and `EmptyState`.
- Status pane already has metric cards, latest self-correction journal, and Run Tests / Sweep / Snapshot actions.
- Sidebar sections currently group panes into Chat, Dashboards, Memory & History, Plugin Surfaces, and Advanced.

## UX Direction

Harness App should feel like a power-user desktop control surface: dense, fast, source-aware, and proof-aware. The goal is not to make it decorative; the goal is to make the next correct action obvious while preserving traceability.

## First Implementation Slice

1. Rename sidebar groups around jobs-to-be-done:
   - `Work`: Projects, Browser.
   - `Observe`: Status, Telemetry, Cost, Tests, Journal, Computer.
   - `Memory`: Memory Fabric, Snapshots, Hooks.
   - `Plugins`: Plugin, Skills, Manifest, Automation.
   - `Run`: Agents, Templates, Eval.
2. Move the sidebar `no test data` footer into a clearer status badge or Tests row treatment.
3. Rework `StatusPane` into:
   - health strip,
   - attention-needed list,
   - collapsible raw self-correction details,
   - stateful action row.
4. Add a shared `ProofBadge` concept for live, cached, stale, unavailable, and unknown states.
5. Apply `ProofBadge` first to Status, Plugin, Memory Fabric, Tests, Agents, and Computer.

## Source-Level Targets

- `Sources/HarnessApp/Support/SidebarSection.swift`: category names, grouping, display order.
- `Sources/HarnessApp/Views/ContentView.swift`: sidebar footer behavior, selection/search affordance.
- `Sources/HarnessApp/Views/StatusPane.swift`: health strip, attention-needed block, action states.
- `Sources/HarnessApp/Support/PaneHeader.swift`: optional provenance/proof slot if needed.
- `Sources/HarnessApp/Support/EmptyState.swift`: proof-aware secondary text and action copy.
- New `Sources/HarnessApp/Support/ProofBadge.swift`: reusable proof state styling.

## Verification

- `swift build`
- Launch via `script/build_and_run.sh`
- Capture live screenshots at default and narrow-ish window sizes.
- Check dark mode contrast, sidebar clipping, keyboard navigation, and VoiceOver labels for icon-only controls.
- Confirm UI copy does not imply live proof when the app only has cached or missing `.ncode` data.

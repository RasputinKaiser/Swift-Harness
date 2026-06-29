# Contributing

Thanks for taking a look at Swift Harness.

Swift Harness is a local-first macOS control surface for NCode and the Self-Improvement-Plugin workflow. Contributions are welcome, but changes should stay focused on the desktop harness loop.

## Good contribution areas

- SwiftUI pane polish
- Harness status and script integration
- NCode stream JSON parsing
- Memory Fabric browsing
- Snapshot and hook event surfaces
- Eval UI and runner behavior
- Browser IPC safety
- Documentation fixes
- Build and bundle scripts

## Before opening a pull request

1. Keep the change scoped.
2. Avoid committing local transcripts, private repo paths, API keys, screenshots with private data, generated `.ncode` state, or personal app logs.
3. Build the app:

```bash
swift build
```

4. Run the app locally if your change touches UI or runtime behavior:

```bash
script/build_and_run.sh
```

5. Mention what changed, why it changed, and how you tested it.

## Pull request style

A good PR includes:

- a short summary
- the reason for the change
- screenshots for UI changes when safe
- build output or manual verification notes
- any known tradeoffs

For larger changes, open an issue first so the design can be discussed before code is written.

## Local data warning

This app reads local harness state and may display local transcripts, paths, Memory Fabric records, hook events, and browser content. Do not include private local data in public issues or pull requests unless it is sanitized.

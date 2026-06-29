# Security Policy

## Supported versions

This project is in active development. Security fixes target the current `main` branch unless a release branch is created later.

## Reporting a vulnerability

Do not open a public issue for a security problem.

Instead, report the issue privately through GitHub's private vulnerability reporting flow if it is enabled for this repository. If that is not available, contact the maintainer through the GitHub profile.

Please include:

- what the issue is
- how it can be reproduced
- what app surface is involved
- whether the issue can expose local files, tokens, transcripts, browser data, screenshots, Memory Fabric records, or private repo content

## Scope

Relevant issues include:

- unsafe subprocess behavior
- local file exposure
- transcript, prompt, or Memory Fabric record exposure
- browser IPC command bypasses
- browser URL or JavaScript gate bypasses
- screenshot leakage
- token or cost data exposure
- bundle or signing behavior that can affect local security

## Out of scope

Please do not report:

- issues caused by publishing your own secrets
- problems in unrelated NCode, Codex, or third-party plugins
- missing features
- theoretical issues without a plausible path to impact

## Local data warning

Swift Harness runs local subprocesses, reads local harness state, opens a local browser IPC socket, and can display browser content. Treat `.ncode` data, transcripts, Memory Fabric records, screenshots, app logs, and browser state as private unless reviewed and sanitized.

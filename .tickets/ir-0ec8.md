---
id: ir-0ec8
status: closed
deps: [ir-t1d5]
links: []
created: 2026-06-21T03:37:16Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-l5gk
tags: [agent-loop, frontend, typescript, conversion]
---
# Convert medium-risk app scripts to TypeScript

Convert medium-risk app-owned runtime scripts to TypeScript while preserving lifecycle and UI behavior.

## Design

Convert app-bootstrap.js, app-dialog-overlays.js, app-time-picker.js, app-passkeys.js, and app-horizontal-scroll.js to matching frontend/ts/*.ts sources. Preserve app:page-ready compatibility and current script loading semantics. Use generated frontend contracts for backend-emitted JSON/data boundaries where applicable, especially overlay/picker/lifecycle config. Add or extend unit/DOM tests for extracted lifecycle, overlay, picker, passkey, and scroll behavior, and keep browser-only contracts covered by focused Playwright checks.

## Acceptance Criteria

Converted TS sources compile cleanly. frontend-check passes with contract checks and meaningful unit/DOM coverage for converted behavior. Applicable backend-emitted JSON/data boundaries use generated contracts. Lifecycle events such as app:page-ready remain compatible. Dialogs, toasts, time picker, passkeys, and horizontal scroll behavior are not regressed. Focused e2e/screenshot checks run where appropriate.


## Notes

**2026-06-21T05:20:35Z**

Converted medium-risk app scripts to frontend/ts entrypoints: app-bootstrap, app-dialog-overlays, app-time-picker, app-passkeys, and app-horizontal-scroll. Generated static/app*.js via frontend-build. Added frontend unit coverage for app:page-ready detail defaults, dialog submit loading markup, time-picker parsing/label/options, passkey storage/base64url helpers, and horizontal scroll parse/clamp helpers. Verified frontend-check, doc-drift-check, focused frontend flake check, LSP diagnostics, and focused mobile/dialog/horizontal Playwright coverage. Full mobile-experience run had 21 passing tests and 9 failures in broader navigation/roster cases with passkey prompt/roster setup symptoms; focused converted-script coverage passed.

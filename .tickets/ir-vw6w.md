---
id: ir-vw6w
status: closed
deps: [ir-0ec8]
links: []
created: 2026-06-21T03:37:17Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-l5gk
tags: [agent-loop, frontend, typescript, live-updates, conversion]
---
# Convert live-update runtime to TypeScript

Convert app-live-updates.js to TypeScript while preserving the strict live-surface contract.

## Design

Move app-live-updates.js source to frontend/ts/app-live-updates.ts and compile back to static/app-live-updates.js. Preserve live-update protocol, payload semantics, cleanup, fragment swap, version-gap, and focused-field protection behavior. Use generated Haskell-owned frontend contracts for live-update surface config, messages, and related backend-emitted JSON/data boundaries. Extract testable protocol/payload/focus-protection decisions into importable modules where practical and cover them with unit/DOM tests, while retaining Playwright as the authority for websocket, HTMX, and multi-viewer behavior.

## Acceptance Criteria

app-live-updates.ts compiles to the existing static asset. frontend-check passes with contract checks and meaningful unit/DOM coverage for converted live-update behavior. Live-update config/message boundaries use generated Haskell-owned TS contracts. No live-update protocol or payload semantics change. Existing live-update/declarative adapter e2e coverage passes. Cleanup, fragment swap, and focused-field protection behavior remains intact.


## Notes

**2026-06-21T05:25:50Z**

Converted app-live-updates to frontend/ts/app-live-updates.ts and regenerated static/app-live-updates.js. Expanded Haskell-owned generated frontend contracts with live-update scope, fragment, command, and message wire types; app-live-updates imports those contracts at the browser boundary. Added frontend unit tests for subscribe command construction, scope key/version normalization, fragment merge keys, and version-gap/empty-fragment resync decisions. Verified frontend-check, frontend-contracts drift via frontend-check, typecheck Application/Script/GenerateFrontendContracts.hs, doc-drift-check, focused frontend flake check, and LSP diagnostics. Ran live-update-declarative-adapter e2e: 9 passed; the remaining failure is the existing roster declarative surface expectation for legacy roster-content fragments versus current split roster fragments, not a runtime JS error.

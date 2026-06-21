---
id: ir-vw6w
status: open
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


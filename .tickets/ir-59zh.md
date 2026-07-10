---
id: ir-59zh
status: open
deps: [ir-zel6]
links: []
created: 2026-07-10T05:32:28Z
type: bug
priority: 1
assignee: beaudan
parent: ir-zpyz
tags: [agent-loop, frontend-surface, typescript, guardrails]
---
# Remove raw data-bepis interaction string leaks

Fix guard failures where production Haskell or handwritten TypeScript directly authors canonical data-bepis interaction strings instead of generated helpers/constants.

## Design

Inspect Web/Controller/RosterWeeks.hs, frontend/ts/app-dialog-overlays.ts, and frontend/ts/interaction/pointer-session.ts. Replace direct guarded strings with generated helpers/constants or approved non-interaction app-shell/dialog contracts. If a string is intentionally outside the interaction contract, narrow the guard allowlist with documentation and tests.

## Acceptance Criteria

SurfaceGuardSpec passes. FrontendContractsSpec generated-string leak test passes. Handwritten TypeScript runtime does not duplicate canonical generated interaction strings.


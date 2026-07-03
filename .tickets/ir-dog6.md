---
id: ir-dog6
status: open
deps: [ir-zu3i]
links: []
created: 2026-07-03T04:17:38Z
type: chore
priority: 1
assignee: Beaudan Brown
parent: ir-7huc
tags: [agent-loop, frontend, live-updates, cleanup]
---
# Delete legacy browser live-surface adapter

## Design

Remove the browser [data-live-update-surface] scan/read/decorate path and legacy declarative live-surface tests, or rewrite them to FrontendSurface. Update E2E expectations and add guardrails banning production data-live-update-surface.

## Acceptance Criteria

Browser runtime only discovers data-bepis-surface-config for live surfaces. No production/static TypeScript legacy live-surface adapter remains. Frontend tests cover generic generated subscription parsing.


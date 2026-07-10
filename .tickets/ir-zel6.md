---
id: ir-zel6
status: open
deps: []
links: []
created: 2026-07-10T05:32:28Z
type: bug
priority: 1
assignee: beaudan
parent: ir-zpyz
tags: [agent-loop, frontend-surface, roster, hspec]
---
# Align roster FrontendSurface interaction contract and Hspec expectations

Investigate and fix backend Hspec failures in FrontendSurface roster contract specs. Confirm intended contract names such as drop-roster-staff, shift-drag-source, staff-drag-source, and roster vs roster-day-timeline drag-source, then align Haskell surface definitions, generated TypeScript contracts, rendered roster markup, and Hspec expectations.

## Design

Start with Web/RosterWeeks/FrontendSurface.hs, Application/Helper/FrontendContract/Surface modules, Test/FrontendSurface* specs, and roster fragment specs. Do not update expectations until generated/rendered behavior is confirmed as the intended contract.

## Acceptance Criteria

Focused FrontendSurface Hspec passes via bash ./bin/in-env hspec-test --match FrontendSurface. frontend-contracts-check passes. frontend-check passes. Any changed expectations reflect intentional generated/rendered behavior.


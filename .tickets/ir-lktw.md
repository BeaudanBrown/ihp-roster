---
id: ir-lktw
status: open
deps: [ir-75hc]
links: []
created: 2026-07-07T03:54:41Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-6rnm
tags: [agent-loop, roster, timeline, docs, tests]
---
# Add roster day timeline coverage, docs, and polish

Finish the timeline epic with tests, docs, and final verification.

## Design

Add or extend Hspec coverage for controller validation, row-index placement, visibility/editability rules, and rendered surface refs/forms. Add focused frontend or Playwright coverage for pointer drag if stable and not prohibitively expensive; otherwise record a clear deferral note. Update Web/RosterWeeks/SPEC.md and README.md with implemented timeline behavior and non-goals, and add a docs/workstreams entry only if future timeline work remains after this slice.

## Acceptance Criteria

Focused roster Hspec passes. typecheck passes. frontend-contracts-check/frontend-check pass if generated contracts or TypeScript changed. Any E2E coverage is run or explicitly deferred with rationale. Living docs describe the timeline view, permissions, drag-to-move behavior, non-goals, and future resize/title follow-ups. Epic acceptance criteria are verified before closeout.


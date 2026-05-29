---
id: ir-5m6b
status: open
deps: [ir-ez90]
links: []
created: 2026-05-29T03:16:11Z
type: task
priority: 3
assignee: beaudan
parent: ir-78cn
tags: [agent-loop, tests, guardrails]
---
# Add guardrail tests for unified fragment conventions

Add or update tests that prevent regression to duplicate actor/live DOM update paths.

## Design

Extend existing strict API/MutationBoundary/LiveSurface guard specs to catch raw actor-only OOB helpers, page live fragments, and direct successful hx-target outerHTML forms where the unified helper should be used.

## Acceptance Criteria

Guardrail tests fail on representative obsolete patterns and pass on the migrated codebase.


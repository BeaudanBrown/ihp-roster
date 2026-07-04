---
id: ir-fh80
status: open
deps: [ir-gaxt]
links: []
created: 2026-07-04T03:20:00Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-888o
tags: [agent-loop, surfaces, interaction, deletion]
---
# Delete legacy semantic marker runtime and helpers

Remove the old semantic marker protocol after all production paths have migrated.

## Design

Remove old runtime paths that infer behavior from semantic attrs such as `data-bepis-session-kind`, `data-bepis-session-intent`, `data-bepis-activation-intent`, `data-bepis-activation-trigger`, and broad `data-bepis-marker` semantics. Remove or shrink old helper exports, delete stale tests or rewrite them to generated-ref runtime, and remove dual-runtime compatibility code.

## Acceptance Criteria

- No old semantic interaction runtime remains in production.
- No public helper API encourages old semantic marker authoring.
- Guardrails prevent reintroduction.
- Frontend tests pass without legacy runtime.
- The epic cannot close until this deletion ticket is complete.

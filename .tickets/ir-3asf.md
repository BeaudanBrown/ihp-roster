---
id: ir-3asf
status: closed
deps: [ir-jqeu]
links: []
created: 2026-04-29T04:45:48Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-5uzu
tags: [area:live-fragments, source:plans-62]
---
# Generalize projection-backed live fragments

Phases 5-7 from plans/62-live-fragment-system-refactor.md: tie projection fragment enums to live fragment refs, add standard render helpers/cache hooks, optimize mounted-fragment fanout/batching, and adopt live fragments only for stale-DOM surfaces with real product need.

## Acceptance Criteria

Projection helpers can power additional surfaces without bespoke fragment builders; performance hooks avoid over-broadcasting high-churn surfaces; wider adoption remains scoped to confirmed stale-DOM workflows.


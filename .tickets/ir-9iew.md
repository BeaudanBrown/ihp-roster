---
id: ir-9iew
status: open
deps: []
links: []
created: 2026-06-30T09:54:22Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-si7h
tags: [architecture, bepis-actions, agent-loop]
---
# Add mutation audit/realtime drift guards during transition

Until all mutations are pipeline-backed, add deterministic checks that descriptive specs agree with visible effects.

## Design

Extend architecture gate to warn/fail when audit-required specs lack audit helper evidence, realtime-required specs lack LiveMutationResult/invalidation evidence, or action wrapper identity drifts. Allow explicit named exceptions only when documented.

## Acceptance Criteria

Strict gate catches missing audit/realtime evidence for legacy spec-backed mutations; existing tree passes or has documented exceptions.


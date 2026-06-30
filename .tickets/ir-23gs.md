---
id: ir-23gs
status: in_progress
deps: [ir-mwma, ir-xz3b, ir-gt0e, ir-glwa, ir-ufjf]
links: []
created: 2026-06-30T11:03:28Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-z0j1
tags: [architecture, bepis-actions, agent-loop]
---
# Replace action wrappers with final runBepis fact runner

Collapse page/form/fragment/dialog/mutation/preference/export/integration wrappers around the single root operation/fact model.

## Design

Replace separate wrapper metadata and mutation-spec arguments with one final API such as runBepis currentAction BepisMutationOperation do ... . The runner opens the fact collector, emits the action fact, runs the IHP action body, summarizes collected facts to telemetry, and applies only narrow safety checks.

## Acceptance Criteria

All controllers can compile using the final runner API; no BepisMutationSpec parameter remains; no legacy bepis*Action wrapper remains unless it is a final facade backed by runBepis and BepisFact.

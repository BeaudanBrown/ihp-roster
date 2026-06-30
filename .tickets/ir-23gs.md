---
id: ir-23gs
status: open
deps: [ir-mwma, ir-xz3b, ir-gt0e, ir-glwa, ir-ufjf]
links: []
created: 2026-06-30T11:03:28Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-z0j1
tags: [architecture, bepis-actions, agent-loop]
---
# Replace action wrappers with final Bepis runner API

Collapse page/form/fragment/dialog/mutation/preference/export/integration wrappers around the single root operation model.

## Design

Replace separate wrapper metadata and mutation-spec arguments with one final API, e.g. runBepis currentAction (bepisPage ...), runBepis currentAction (bepisMutation ...), or equivalent. The runner collects evidence produced by inner helpers and emits telemetry/architecture-visible facts.

## Acceptance Criteria

All controllers compile using the final runner API; no BepisMutationSpec parameter remains; no legacy bepis*Action wrapper remains unless it is the final runner facade backed by the root model.


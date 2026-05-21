---
id: ir-cf17
status: open
deps: [ir-f42m]
links: []
created: 2026-05-21T07:43:26Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-xyzw
tags: [agent-loop, area:roster, area:architecture]
---
# Define reversible roster read-model seam

Add the smallest safe code-level call boundary for choosing projection-backed versus SQL/direct roster data.

## Design

Keep existing projection functions intact. Introduce one wrapper or selection point for roster read data that initially delegates to the projection path. Do not add a runtime env flag unless a later ticket explicitly needs one. Keep RosterRenderData as the output type so callers and render functions remain stable.

## Acceptance Criteria

Roster full-page and fragment callers route through the seam. Default behavior remains projection-backed at this stage. The seam makes rollback to the projection path obvious. Focused roster tests and typecheck pass.


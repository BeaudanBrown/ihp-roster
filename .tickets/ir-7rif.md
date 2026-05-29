---
id: ir-7rif
status: open
deps: [ir-7s9u]
links: []
created: 2026-05-29T03:16:10Z
type: task
priority: 2
assignee: beaudan
parent: ir-kuyy
tags: [agent-loop, roster, renderer]
---
# Add roster shared fragment render mode

Create one roster fragment renderer capable of plain and OOB output for content, staff panel, day sections, and rows.

## Design

Unify renderRosterContentFragmentOob, renderRosterDaySectionFragmentOob, renderRowOob, and staff panel OOB through FragmentRenderMode while keeping exact target nodes for GETs.

## Acceptance Criteria

Roster fragment contract tests cover all fragment targets and containment; existing fragment GET specs pass.


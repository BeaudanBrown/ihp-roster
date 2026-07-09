---
id: ir-i1i9
status: closed
deps: [ir-smzc]
links: []
created: 2026-07-09T01:32:04Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-qbm4
tags: [agent-loop, roster, frontend, css, interaction]
---
# Render roster whole-day dropzones and expanded add-shift highlight

Make day-column drag targets be whole open days while preserving + Add shift click behavior.

## Design

In day-column layout, render the generated dropzone ref on the open editable .roster-day-column section with a semantic day token such as day:<rosterDayId>. Keep the + Add shift card as a dialog launcher but no longer as the drag highlight owner. Add feature-scoped CSS so .roster-day-column.bepis-dropzone-highlight uses the same green/success visual language as the + Add shift card, expanded to the full column.

## Acceptance Criteria

Whole open day columns highlight during drag hover. Highlight visually matches the + Add shift success style, expanded to the column. Closed/non-editable days do not expose dropzones. Clicking + still opens the create dialog.


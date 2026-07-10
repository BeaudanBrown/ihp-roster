---
id: ir-s8k1
status: closed
deps: []
links: [ir-7b1w]
created: 2026-07-10T00:19:58Z
type: bug
priority: 2
assignee: beaudan
parent: ir-z20h
tags: [agent-loop, roster, shift-types, ui]
---
# Show shift-type setup toast before creating roster shifts

Creating a roster shift silently fails or opens an unusable dialog when no shift types exist.

## Design

When a manager opens the new roster shift dialog and the venue has no active shift types, return an explanatory toast through the dialog/toast overlay response instead of rendering the shift form. Keep edit behavior for existing shifts intact.

## Acceptance Criteria

Attempting to add a new roster shift with zero active shift types shows a toast telling the user to create a shift type in Admin > Shift Types first. No empty shift dialog is opened. Venues with active shift types keep the current dialog flow. Focused roster controller tests cover both paths.


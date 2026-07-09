---
id: ir-w5a8
status: open
deps: []
links: []
created: 2026-07-09T02:39:01Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-z20h
tags: [agent-loop, staff, trial, ui]
---
# Add trial-staff invite action in staff list

Expose a compact adoption-invite action beside trial staff in the staff list/panel.

## Design

Add a small add/link-person icon button for trial staff rows, reusing the existing trial staff adoption invitation flow and permissions. Avoid duplicating invitation logic or broadening access.

## Acceptance Criteria

Managers/admins see a clear compact invite action for trial staff. The action launches/sends through the existing adoption flow with existing permission checks. Linked/non-trial staff do not show the trial invite action.


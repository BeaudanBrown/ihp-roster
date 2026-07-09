---
id: ir-xqwe
status: open
deps: []
links: []
created: 2026-07-09T02:39:01Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-z20h
tags: [agent-loop, roster-groups, admin, ui]
---
# Hide roster-group config for single-group venues

Suppress unnecessary roster-group configuration where a venue only has one roster group.

## Design

Identify admin, staff, invite, and roster filters/forms that expose roster-group controls. Hide or simplify controls when exactly one active roster group exists while preserving hidden/default values needed by forms and routes.

## Acceptance Criteria

Single-group venues do not see unnecessary roster-group selection/config clutter. Multi-group venues keep existing controls. Forms continue submitting valid rosterGroupId/default scope values. Focused admin/roster tests pass.


---
id: ir-xqwe
status: closed
deps: []
links: [ir-7b1w]
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

For the immediate roster-page polish pass, hide the roster page header group switcher when the current venue has only one active roster group. Week navigation and HTMX routes should still carry the current/default roster group id internally so URLs, live scopes, and form submissions remain valid. Multi-group venues keep the existing switcher.

## Acceptance Criteria

- Single-group venues do not see unnecessary roster-group selection/config clutter.
- The roster page header does not render the roster group dropdown when only one active roster group exists.
- Multi-group venues keep the roster group dropdown and existing switching behavior.
- Forms continue submitting valid rosterGroupId/default scope values.
- Focused admin/roster tests pass.


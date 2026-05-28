---
id: ir-q13w
status: open
deps: []
links: []
created: 2026-05-28T05:42:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-sky7
tags: [area:admin, area:roster-groups, area:ui, agent-loop]
---
# Convert roster group active status to toggle and remove Default badge

Simplify roster group rows by using toggles and hiding default badges.

## Design

In Web.View.Admin.RosterGroups, replace active/inactive selects with shared toggle controls and remove renderRosterGroupDefaultBadge from row chrome. Preserve the rule that each venue must have at least one active roster group and keep ordering controls unchanged.

## Acceptance Criteria

Roster group create/edit rows use shared active toggles; no Default badge is rendered; at-least-one-active validation still works; admin roster-group tests are updated.


---
id: ir-t4g3
status: open
deps: [ir-fp76, ir-5dd9, ir-a02h]
links: []
created: 2026-06-29T13:12:15Z
type: feature
priority: 2
assignee: beaudan
parent: ir-21jr
tags: [agent-loop, roster, lazy-loading, ui-regions]
---
# Migrate roster staff panel lazy loading to declarative region capabilities

Use the new declarative UI region capability attrs for RosterProjectionStaffPanel.

## Design

Keep ShowRosterWeekStaffPanelFragmentAction as the authoritative endpoint, preserve root id roster-staff-panel-fragment, keep server-owned custom placeholder shape, and use immediate lazy load by default without artificial multi-second delay.

## Acceptance Criteria

Roster shell renders first; staff panel placeholder has matching layout geometry; staff panel loads via HTMX into the same root id; retry/error and transition behaviour work through generic region events; focus/live-update compatibility remains unchanged.


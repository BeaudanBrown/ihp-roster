---
id: ir-4dtf
status: open
deps: [ir-uu3x]
links: []
created: 2026-05-29T03:16:10Z
type: task
priority: 2
assignee: beaudan
parent: ir-kuyy
tags: [agent-loop, roster, navigation]
---
# Migrate roster content staff-panel and filter/navigation responses

Convert broader roster actor responses and navigation/filter flows to unified fragments.

## Design

Replace content/staff panel bespoke responses and actor refresh headers where safe; decide whether week/group/filter navigation should target content+panel fragments while preserving horizontal scroll containers.

## Acceptance Criteria

Roster content/staff-panel responses use shared fragments; URL push and live metadata remain correct across week/group/filter changes; scroll behavior is covered if changed.


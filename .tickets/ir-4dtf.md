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
tags: [agent-loop, roster, navigation, frontend-surface]
---
# Migrate roster content staff-panel and navigation responses

Convert broader roster success responses and navigation/filter flows to the semantic invalidation model where they are mutating actor successes, while preserving direct view-state GET behavior.

## Design

Content/staff-panel mutation successes should emit actor-local semantic invalidation plus extras, not business OOB HTML. Week/group/filter navigation and pure view-state GETs may remain direct fragment/page responses when no mutation/passive invalidation is needed. URL push and live metadata must remain correct across week/group/filter changes.

## Acceptance Criteria

Roster content/staff-panel mutation success responses contain no authoritative business OOB. Pure navigation/refetch GET behavior is explicitly classified and remains correct. URL push, surface metadata, and scroll behavior are covered if changed.

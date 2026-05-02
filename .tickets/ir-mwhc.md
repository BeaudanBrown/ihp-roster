---
id: ir-mwhc
status: open
deps: [ir-qi7t]
links: []
created: 2026-04-29T04:41:29Z
type: epic
priority: 4
assignee: Beaudan Brown
tags: [area:auth, area:venue-switching, coordinator:coordinator-hap, backlog]
---
# Ordinary account multi-venue switching

Repo-local backlog feature migrated from coordinator-hap. Adds ordinary user switching among venues where the user has real memberships, without conflating it with founder support access.

## Design

coordinator_ref: coordinator-hap
status: backlog
workstream: docs/workstreams/backlog.md
blocked_by: support-access product separation and real multi-membership UX decision

## Acceptance Criteria

Ordinary users can switch only among venues where they hold real memberships, using currentVenueId safely and separately from founder support access.

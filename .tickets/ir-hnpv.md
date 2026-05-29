---
id: ir-hnpv
status: open
deps: [ir-jtmv]
links: []
created: 2026-05-29T03:16:08Z
type: task
priority: 1
assignee: beaudan
parent: ir-5v0t
tags: [agent-loop, research, confirmation]
---
# Confirm admin surface migration order and focus constraints

Research current admin simple surfaces and confirm which can be migrated together safely.

## Design

Inspect VenueSettings, Invites, Exports, RosterGroups, ShiftTypes, Admin controller mutation responses, existing focus protection, and any recent tickets affecting admin config. Confirm whether shift types/roster groups need special handling because of focused-field protection or row editing.

## Acceptance Criteria

Ticket note records final migration order, target ids, focused-field constraints, and any sections deferred; no production behavior changes are made.


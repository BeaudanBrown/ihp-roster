---
id: ir-aup5
status: open
deps: [ir-rq2j]
links: []
created: 2026-07-09T02:39:00Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-bw8v
tags: [agent-loop, timesheets, roster]
---
# Materialise expected roster shifts into timesheets

Add a server action to create a concrete linked timesheet from an expected roster shift.

## Design

Add route/controller/mutation flow that accepts a roster slot id, validates current venue, live roster state, linked active staff, slot completeness, permissions, and absence of an active linked entry, then creates an unapproved TimesheetEntry with source_roster_slot_id and roster-derived times/shift type. Reuse timesheet touched-resource invalidation and dialog/toast conventions.

## Acceptance Criteria

Staff can materialise their own expected shifts; managers/admins can materialise visible expected shifts; tampered or stale requests fail safely; duplicate active linked entries are prevented; successful materialisation refreshes the relevant timesheet day/week fragments.


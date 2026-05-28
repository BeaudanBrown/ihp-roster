---
id: ir-s9wv
status: closed
deps: []
links: []
created: 2026-05-28T05:42:05Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-j3eq
tags: [area:xero, area:ui, agent-loop]
---
# Hide Xero timesheet surfaces until connection is active

Show only the Xero connection card when the venue lacks an active Xero connection.

## Design

Adjust Web.View.Admin.Xero rendering so disconnected or non-active connections show only the top connection card/details. Hide draft timesheet submission, mappings, pay items, and other operational panels until the connection is active. Update customer-facing copy in these views from 'IHP timesheets' to 'Bepis timesheets' where applicable.

## Acceptance Criteria

Disconnected/non-active Xero page renders only connection chrome; active connection renders operational panels as before; Xero draft-timesheet copy says Bepis; Xero view tests/e2e are updated.


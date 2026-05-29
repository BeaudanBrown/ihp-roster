---
id: ir-2ert
status: open
deps: []
links: []
created: 2026-05-29T03:16:06Z
type: task
priority: 1
assignee: beaudan
parent: ir-6q3e
tags: [agent-loop, research, confirmation]
---
# Confirm unified fragment helper API against current code

Research the current post-timesheets code, inspect existing OOB helpers, and ask/confirm any API-shape questions before implementing the shared helper.

## Design

Review Application.Helper.LiveSurface, Application.Helper.View.Oob, Web.Timesheets.Responses, roster/leave/admin/Xero response paths, and the latest ticket state. Confirm whether the helper should render immediate OOB HTML only, whether actor-refresh headers remain supported for roster during transition, and where the helper module should live.

## Acceptance Criteria

A note is added to this ticket summarizing confirmed decisions, changed assumptions since the planning scan, and the exact helper API to implement; no production behavior changes are made in this ticket.


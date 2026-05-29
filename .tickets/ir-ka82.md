---
id: ir-ka82
status: open
deps: [ir-6q3e]
links: []
created: 2026-05-29T03:16:07Z
type: task
priority: 1
assignee: beaudan
parent: ir-jtmv
tags: [agent-loop, research, confirmation]
---
# Confirm leave/profile fragment boundaries before migration

Research current leave/profile/roster self-service update paths and confirm the fragment boundaries before implementation.

## Design

Inspect Web.LeaveRequests.Projection, Web.Controller.LeaveRequests, Web.LeaveRequests.ProfileSelfService, Web.Profiles.LiveUpdates, profile view fragments, and roster self-service leave fragment usage. Ask whether profile leave form/list should be one surface or two if unclear after inspection.

## Acceptance Criteria

Ticket note records chosen fragment enum(s), target ids, validation-failure exceptions, and any changes caused by the foundation helper; no production behavior changes are made.


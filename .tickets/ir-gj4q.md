---
id: ir-gj4q
status: open
deps: []
links: []
created: 2026-04-30T06:34:32Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-18tm
tags: [area:leave, area:profile, area:maintenance, area:live-fragments]
---
# Decompose leave requests and profile leave integration

Separate leave request projection, live-surface, response, validation, and profile self-service integration concerns so the leave controller and profile view do not own each others fragment details.

## Design

Create feature-owned leave modules for projection/render data/responses/live updates. Move profile leave fragment refs and adapters behind a narrow self-service/profile-leave boundary, likely extending Application.Helper.ProfileLeave or adding Web.LeaveRequests.SelfService. Preserve the product rule that only approved leave invalidates roster scopes.

## Acceptance Criteria

Web.Controller.LeaveRequests no longer imports profile view fragment refs directly; profile leave markup uses a stable adapter instead of reaching across leave views ad hoc; leave page and profile leave fragments keep stable DOM ids and live-surface metadata; focused leave/profile tests pass.

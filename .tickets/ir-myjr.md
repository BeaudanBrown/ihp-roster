---
id: ir-myjr
status: open
deps: [ir-3y9k]
links: []
created: 2026-05-29T03:16:09Z
type: task
priority: 1
assignee: beaudan
parent: ir-oxnj
tags: [agent-loop, research, confirmation]
---
# Confirm Xero nested fragment and auto-sync constraints

Research current Admin Xero fragment paths and confirm constraints before implementation.

## Design

Inspect Web.View.Admin.Xero, StaffMappings, Controller/Admin/Xero/Responses, Admin controller fragment endpoints, auto-sync trigger forms, dialog OOB paths, and recently completed Xero tickets. Confirm which actor-refresh-header uses should become immediate OOB and which should remain deferred.

## Acceptance Criteria

Ticket note records chosen containment paths, auto-sync handling, dialog/toast extras, and any deferred cases; no production behavior changes are made.


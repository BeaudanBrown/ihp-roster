---
id: ir-myjr
status: open
deps: []
links: []
created: 2026-05-29T03:16:09Z
type: task
priority: 1
assignee: beaudan
parent: ir-oxnj
tags: [agent-loop, research, confirmation, frontend-surface]
---
# Confirm Xero semantic invalidation and extras constraints

Research current Admin Xero fragment paths and confirm constraints before implementation.

## Design

Inspect `Web.View.Admin.Xero`, nested Xero view modules, `Web.Controller.Admin.Xero.Responses`, Admin controller fragment endpoints, auto-sync trigger forms, dialog OOB paths, and existing actor refresh headers. Confirm which success paths should emit shell-level versus child-level semantic invalidations, which paths are validation/dialog-local, and which response HTML is extras-only.

## Acceptance Criteria

Ticket note records selected semantic invalidation fragments, auto-sync handling, dialog/toast extras, duplicate-mount implications, and any deferred cases. No production behavior changes are made.

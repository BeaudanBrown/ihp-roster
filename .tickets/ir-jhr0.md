---
id: ir-jhr0
status: closed
deps: [ir-jkt2]
links: []
created: 2026-04-30T05:43:11Z
type: task
priority: 2
assignee: beaudan
parent: ir-y2wh
tags: [area:style, area:view, area:maintenance]
---
# Migrate repeated status badges to semantic helper

Replace audited repeated Bootstrap status badge markup with Application.Helper.View.Status helpers/classes so common statuses no longer depend on page-local Bootstrap color classes.

## Design

Start from the audit hits in Web/View/LeaveRequests/Index.hs, Web/View/Profiles/Edit.hs, Web/View/RosterWeeks/Overview.hs, Web/View/Admin/Common.hs, Web/View/Admin/Invites.hs, Web/View/Admin/Xero/*, and Web/View/Support/Index.hs. Reuse renderAppStatusBadge/appStatusBadgeClass where labels are simple. Add small focused helper functions only when multiple call sites share the same status mapping. Preserve displayed labels, table layout, role-gating, and ordering. Avoid unrelated Bootstrap class churn.

## Acceptance Criteria

Leave request, invite/onboarding, roster overview, admin common, exports, support job, and Xero readiness/mapping/pay-item status badges use app-status-badge classes or a shared semantic helper where practical; no audited common status renderer returns raw badge text-bg-* or bg-* classes unless documented as feature-specific; bash ./bin/in-env typecheck passes; focused Hspec is added or updated only if a status helper has non-trivial branch behavior.


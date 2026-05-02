---
id: ir-y2wh
status: closed
deps: []
links: [ir-5mdm, ir-a7dt]
created: 2026-04-30T05:42:53Z
type: epic
priority: 2
assignee: beaudan
parent: ir-6vvh
tags: [area:style, area:view, area:maintenance, source:styling-refactor-audit]
---
# Complete styling refactor foundation follow-up

Follow-up work from the 2026-04-30 styling refactor audit. The split CSS/token foundation exists, but four concrete cleanup points remain before the styling architecture can be treated as complete for current scope.

## Design

Scope this parent to the first four incomplete points from the audit: style-audit/asset bookkeeping, semantic status badge migration, generic action menu naming, and shared surface helper migration. Do not include venue theming or visual regression expansion here; those remain later phases of docs/archive/plans/54-styling-system-refactor.md.

## Acceptance Criteria

All four child tickets are closed; bash ./bin/style-audit passes for actionable checks; no remaining non-feature use of roster-week-more-menu; repeated status badges in the audited leave/admin/support/export/overview surfaces use Application.Helper.View.Status; repeated border rounded p-* surfaces in the audited Xero/admin/profile areas are converted to app surface/panel helpers where appropriate.


---
id: ir-8yyg
status: in_progress
deps: [ir-fv82]
links: []
created: 2026-04-30T01:11:35Z
type: task
priority: 1
assignee: beaudan
parent: ir-23k7
tags: [area:xero, area:view, area:admin, area:maintenance, source:2026-04-30-health-scan]
---
# Split Xero admin view sections

Split Web/View/Admin/Xero.hs into section modules for connection, sync status, staff mappings, earnings/pay items, calendars, and readiness while preserving DOM ids.

## Design

Use the read-model records from `ir-fv82` as the view boundary. The goal is to
make each Xero admin section easy to find and edit without changing rendered
markup.

Candidate modules:

- `Web.View.Admin.Xero.Connection`
- `Web.View.Admin.Xero.Sync`
- `Web.View.Admin.Xero.StaffMappings`
- `Web.View.Admin.Xero.EarningsMappings`
- `Web.View.Admin.Xero.PayItems`
- `Web.View.Admin.Xero.Calendars`
- `Web.View.Admin.Xero.Readiness`

Keep `Web.View.Admin.Xero` as the import/re-export boundary that assembles the
full Xero admin page and exposes the public render functions expected by the
controller.

Guardrails:

- Preserve every stable `id`, `data-live-update-surface`, `hx-*` attribute,
  `hx-swap-oob`, form field name, and toast mount target.
- Move duplicate normal/OOB render pairs to the shared OOB rendering helper only
  after `ir-2vyr` is ready; do not block this view split on that helper.
- Avoid visual cleanup and Bootstrap class churn in the same slice.

## Acceptance Criteria

- Xero connection, sync, staff mapping, earnings/pay item, calendar, and
  readiness markup lives in focused modules or clearly named local render
  groups.
- The top-level Xero view module is short and primarily composes sections.
- Existing Xero fragment Hspec assertions still find the same DOM ids and OOB
  attributes.
- Focused Xero Playwright coverage still passes.

## Notes

**2026-04-30T01:27:34Z**

Started Xero view split. Extracted StaffMappings, Calendars, and Readiness modules while preserving existing DOM ids/HTMX/OOB attributes. Verified with bash ./bin/in-env typecheck and bash ./bin/in-env hspec-test --match "Xero". Remaining: connection/sync and pay-item section modules before closing.

---
id: ir-fv82
status: closed
deps: []
links: []
created: 2026-04-30T01:11:30Z
type: task
priority: 1
assignee: beaudan
parent: ir-23k7
tags: [area:xero, area:admin, area:maintenance, source:2026-04-30-health-scan]
---
# Extract Xero admin read models and query loaders

Move Xero admin page data loading, readiness summaries, reference-data counts, and mapping query bundles out of the controller into narrow read-model helpers.

## Design

Start with behavior-preserving extraction only. The first pass should make the
controller call named loader functions without changing routes, DOM, HTMX
targets, or Xero API behavior.

Candidate records:

- `XeroAdminPageData` for connection state, sync metadata, mapping counts, pay
  item requirements, payroll calendars, and readiness summaries.
- `XeroStaffMappingData` for IHP staff, Xero employees, existing mappings,
  suggested matches, and matched/unmatched counts.
- `XeroEarningsMappingData` for shift/earnings buckets, available Xero earnings
  rates, existing mappings, and missing requirement rows.
- `XeroReadinessData` for timesheet submission blockers and checklist rows.

Candidate helper functions:

- load the current venue's active Xero connection and tenant details once.
- load Xero reference-data counts from stored sync rows.
- build staff and earnings mapping suggestions through pure helpers where
  possible.
- build readiness summaries from existing helper modules without duplicating
  readiness logic in the controller.

Guardrails:

- Do not alter OAuth token handling, API calls, or persistence semantics in this
  ticket.
- Keep all new helpers venue-scoped through the current venue id.
- Prefer plain records over typeclass-heavy abstractions; this is a navigation
  refactor, not a framework change.

## Acceptance Criteria

- `Web.Controller.Admin.Xero` delegates page/fragment data loading to focused
  read-model helpers.
- Repeated Xero query bundles in page and fragment actions are gone or routed
  through one named loader.
- Pure suggestion/count/readiness builders have focused Hspec coverage where
  extracting them exposes a useful seam.
- `bash ./bin/in-env typecheck` passes after the extraction.

## Notes

**2026-04-30T01:23:31Z**

Extracted Xero admin read/query loaders and pure staff suggestion/count/checklist builders into Application.Xero.Admin.ReadModel. Verified with bash ./bin/in-env typecheck and bash ./bin/in-env hspec-test --match "Xero".

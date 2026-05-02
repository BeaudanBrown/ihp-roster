---
id: ir-p9kg
status: closed
deps: [ir-tgkr]
links: []
created: 2026-04-30T00:09:48Z
type: feature
priority: 1
assignee: beaudan
parent: ir-shsr
tags: [area:xero, area:payroll, readiness]
---
# Add Xero readiness blocker diagnostics

Define and expose structured readiness blockers for Xero payroll submission: blocker code, severity, human message, affected staff/pay bucket/source entry/Xero object, and suggested admin action. This should be reusable by the Admin Xero checklist, the future preview page, and tests.

## Design

Use `docs/archive/plans/63-xero-timesheet-submission.md` as the blocker catalog. The first
shape can live in a helper module rather than a controller. It should support
both blocker and warning severities and identify affected local/Xero objects when
known.

## Acceptance Criteria

- Blockers have stable machine-readable codes.
- Blockers carry enough data for Admin Xero and future preview/submission UI to
  render actionable messages.
- The validator can return blockers without performing Xero writes.
- Tests assert blocker codes, not only message text.

## Notes

**2026-04-30T00:40:46Z**

2026-04-30: Implemented Xero draft-timesheet foundation slice through readiness validation. Added Payroll AU Timesheets client support, submission persistence tables/types/schema checks, structured readiness blockers/validator, employee-period duplicate detection, and Admin Xero readiness checklist alignment. Verified with regen-types, typecheck, and focused Xero/Schema Hspec.

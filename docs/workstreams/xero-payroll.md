# Xero Payroll Integration

Status: active

Tickets:

- `ir-176p` - parent epic
- `ir-mjov` - connection foundation maintenance
- `ir-adtf`, `ir-shsr`, `ir-lgy7`, `ir-tfed`, `ir-ujwc`, `ir-z87w`

Living docs to update:

- `Application/Xero/README.md`
- `Application/Xero/SPEC.md`
- `Application/Xero/AGENTS.md`
- `Web/Controller/Admin/Xero/AGENTS.md`
- `Application/Helper/Export/SPEC.md`

Archived context:

- `docs/archive/plans/57-xero-payroll-integration.md`
- `docs/archive/plans/58-xero-connection-foundation.md`
- `docs/archive/plans/63-xero-timesheet-submission.md`
- `docs/archive/plans/64-xero-openapi-contract-and-probes.md`

## Goal

Connect approved, reproducible IHP payroll data to Xero Payroll AU through
managed pay items and draft timesheet submission.

## Current State

The app has Xero connection, owner-only management, reference-data sync, pay
item foundations, readiness surfaces, preview builders, and probe scripts in
various stages. Open work remains around readiness UI, preview/submission,
audit trails, correction behavior, and custom pay item overrides.

## Intended Contract

- Xero management is visible only to venue owners and super admins.
- OAuth/session/security flows remain native full-page flows unless there is a
  concrete in-place workflow need.
- Payroll submission uses approved timesheets with locked pay version context.
- Xero remains payroll/tax/STP authority; Bepis does not calculate tax.
- Submission records should be auditable and should prevent silent destructive
  edits to submitted rows.

## Exit Criteria

- Xero preview and submission use the same locked payroll facts as exports.
- Readiness surfaces clearly show missing staff, pay item, and mapping inputs.
- Submission results and errors are auditable.
- Living Xero docs replace archived plan instructions for future agents.

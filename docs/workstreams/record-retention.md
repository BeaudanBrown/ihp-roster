# Record Retention And Soft Deletion

Status: active

Tickets:

- `#106` - parent epic
- `#66`, `#115`, `#85`, `#17`

Living docs to update:

- `specs/02-domain-model.md`
- `specs/10-au-saas-security-privacy-compliance/`
- `Web/Timesheets/SPEC.md`
- `Web/LeaveRequests/SPEC.md`
- `Application/Helper/Export/SPEC.md`

Archived context:

- `docs/archive/plans/55-record-retention-soft-deletion.md`

## Goal

Make soft deletion or deactivation the default for protected business records
before paid venue data is treated as production.

## Current State

Timesheet, leave, role, export, and audit history already have some
provenance-focused paths. Remaining work is to inventory destructive paths,
add schema guardrails, and migrate controller/admin behavior.

## Intended Contract

- Payroll-adjacent records are corrected through additive history or explicit
  reset flows, not silent hard deletion.
- Protected roster, timesheet, leave, export, audit, and configuration records
  have clear deletion semantics.
- Operations notes describe any allowed retention/destruction path.

## Exit Criteria

- Destructive paths are inventoried and covered by tests.
- Protected-record constraints exist where the schema can enforce them.
- Subsystem specs describe deletion/correction behavior.

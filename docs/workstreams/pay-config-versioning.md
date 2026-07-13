# Append-Only Pay Config Versioning

Status: implemented

Living docs to update:

- `Application/Helper/Export/SPEC.md`
- `Web/Timesheets/SPEC.md`
- `Application/Xero/SPEC.md`
- `specs/02-domain-model.md`
- `specs/06-pay-engine.md`
- `Test/AGENTS.md`

Archived context:

- `docs/archive/plans/68-append-only-pay-config-versioning.md`
- `docs/archive/plans/65-spec-agent-doc-alignment.md`

## Goal

Make payroll-adjacent history reproducible without depending on mutable current
configuration.

The target invariant is:

```text
approved/exported/submitted payroll record + stored version ids = stable historical result
```

## Current State

The implementation direction has moved away from JSON `pay_config_snapshots`
toward append-only relational pay configuration versions. Existing snapshot
plans remain audit context only. The parent ticket is closed; keep this
workstream as a transition record until all future agents rely on living specs
instead of the archived plan.

## Intended Contract

- Approved timesheets store the staff and shift-type pay version ids used at
  approval time.
- Exports and Xero submissions record the approved entries and version context
  they include.
- Draft and unapproved records may resolve current active config.
- FWC/MAPD award-rate rows keep their raw operative dates, while current
  calculations resolve those dates through the venue week-start rollover rule
  documented in `specs/06-pay-engine.md`.
- Pay-relevant admin edits append new version rows instead of mutating facts
  used by locked historical rows.
- The JSON snapshot system should be removed after relational versioning fully
  replaces it.

## Pay-Relevant Facts

Versioning must cover facts that affect pay, export, or Xero interpretation:

- staff default award level and employment basis
- shift type pay mapping and payroll label
- award level labels and rates
- base and penalty rates by employment basis and operative dates
- public holiday applicability that changes pay
- timesheet shift type, worked date, start/end, break, and staff

## Exit Criteria

- `pay_config_snapshots` and `pay_config_snapshot_id` runtime usage is gone.
- Approval, export, and Xero flows use relational version ids.
- Golden payroll/export tests prove output stability after config changes.
- Living docs describe the implemented version tables and locking gates.

# Append-Only Pay Config Versioning

Created: 2026-04-30

## Status

Current direction: replace the JSON `pay_config_snapshots` system with
append-only relational pay configuration versions and explicit locking gates.

This plan supersedes the JSON-snapshot implementation direction in
`ir-3vc6` and `ir-lz0x`. Those tickets remain useful as audit references for
the reproducibility problem, but implementation should proceed through
`ir-hw2v` and its children.

## Goal

Payroll-adjacent history must be reproducible without depending on mutable
current configuration. Approved timesheets, exports, and Xero submissions should
reference immutable relational version rows, not a copied JSON snapshot payload.

The desired invariant is:

```text
approved/exported/submitted payroll record + stored version ids = stable historical result
```

Draft and unapproved records may resolve the current active version. Once a
record passes a locking gate, later config changes must create new version rows
for future records instead of mutating the facts used by old records.

## Tracker

Primary epic:

- `ir-hw2v` - Replace JSON pay snapshots with append-only pay config versions

Children:

- `ir-vgdg` - Design append-only pay config version schema
- `ir-srwi` - Implement relational pay config versions and calculation resolution
- `ir-f7j7` - Convert pay-relevant admin edits to append-only version actions
- `ir-6s3f` - Add approval export and Xero locking gates
- `ir-d1po` - Remove pay_config_snapshots JSON system
- `ir-3qku` - Update payroll reproducibility specs and agent docs for versioned config

Related/superseded:

- `ir-3vc6` - originally targeted fixing JSON snapshot calculation
- `ir-lz0x` - originally targeted JSON snapshot foundation
- `ir-caf4` - broader V1 schema hardening epic
- `ir-z5dj` - payroll terminology/docs alignment

## Design Principles

- Use relational version ids as the operational source of truth.
- Keep immutable rows immutable after they are referenced by approval, export, or
  Xero submission.
- Use append-only replacements, effective dating, and supersession instead of
  in-place mutation for pay-relevant facts.
- Keep display/admin records separate from historical pay facts where possible.
- Do not create pay versions for non-pay changes such as sort order unless the
  field is exported/submitted or otherwise payroll-relevant.
- Remove `pay_config_snapshots` entirely once relational versioning replaces it;
  do not keep JSON snapshots as a parallel source of truth.

## Pay-Relevant Facts

The first design pass should enumerate every current input used by
`calculate_timesheet_pay`, payroll exports, and Xero timesheet submission.
Current known inputs include:

- timesheet entry worked date, start/end time, break details, staff id, and shift
  type id
- shift type pay mapping to an override award level
- shift type label when used in export/Xero tracking or descriptions
- staff default award level
- staff employment basis
- award level identity and human-readable classification label
- base rates by award level, employment basis, and operative date
- penalty rates by award level, employment basis, penalty kind, and operative
  date
- public holiday jurisdiction and public holiday rows
- any accepted award/rate release that changes future applicable rates

## Proposed Schema Shape

The exact schema should be finalized in `ir-vgdg`, but the intended shape is:

```text
shift_types
  id
  venue_id
  stable display/admin fields

shift_type_pay_versions
  id
  venue_id
  shift_type_id
  award_level_id
  label_for_payroll
  effective_from
  effective_to
  superseded_by_id
  created_by_user_id
  created_at
  locked_at

staff_pay_versions
  id
  venue_id
  staff_id
  default_award_level_id
  employment_basis
  effective_from
  effective_to
  superseded_by_id
  created_by_user_id
  created_at
  locked_at

accepted_award_rate_versions
  id
  award_level_id
  employment_basis
  penalty_kind/base marker
  hourly_rate
  operative_from
  operative_to
  source fwc/mapd identifiers
  accepted_by_user_id
  accepted_at

timesheet_entries
  shift_type_id
  shift_type_pay_version_id
  staff_pay_version_id
  approval/export/submission lock fields as needed
```

Rate rows may reuse existing `award_level_base_rates` and
`award_level_penalty_rates` if they are made append-only and immutable once
accepted. If existing tables remain mutable, introduce replacement version tables
instead.

## Version Creation Triggers

Create a new version when a change can alter payroll interpretation:

- applying/accepting a new award or rate release
- changing a shift type's award-level mapping
- changing a shift type label used in payroll exports or Xero payloads
- changing a staff member's default award level
- changing a staff member's employment basis
- changing venue/public-holiday jurisdiction if it affects pay
- changing any rate, penalty, allowance, or rule used by pay calculation

Do not create a pay version for:

- shift type sort order
- roster-only grouping/order changes
- visual/admin labels that are not used in pay/export/Xero history
- draft-only UI state

## Locking Gates

Approval, export, and Xero submission should be explicit gates.

### Timesheet Approval

Approval should resolve the current active version ids and store them on the
approved entry. After approval, calculation must use those ids. Editing an
approved entry should either reset approval before export/submission, or create
an auditable correction flow once it has been exported/submitted.

### Export Generation

Export generation should record exactly which approved entries and version ids
were included. Introduce an export membership/provenance table if needed. Once
included in an export, an entry should not be silently destructively edited.

### Xero Preview/Submission

Xero preview/submission should record included entry ids and version ids. A
submitted entry should require reversal/amendment behavior instead of ordinary
mutation.

## Migration Strategy

1. Add relational version tables and current-version resolution helpers.
2. Backfill version rows from current data for development/test fixtures.
3. Add version references to `timesheet_entries` and export/Xero provenance.
4. Update approval to store version ids.
5. Update `calculate_timesheet_pay` and exports to use version ids for approved
   entries.
6. Update admin mutation flows to append new versions for pay-relevant changes.
7. Add locking gates for export and Xero flows.
8. Remove `pay_config_snapshots`, `pay_config_snapshot_id`, JSON snapshot helper
   code, tests, fixtures, and docs.

Do not keep both systems as long-term parallel mechanisms. A short migration
bridge is acceptable inside one implementation slice, but acceptance for
`ir-d1po` is full removal.

## Test Strategy

Add focused regression coverage for:

- approving an entry stores shift/staff/rate version ids
- changing a shift type pay mapping creates a new version and leaves old
  approved pay unchanged
- changing a staff default award level creates a new version and leaves old
  approved pay unchanged
- accepting new base/penalty rates creates new future-applicable versions and
  leaves old approved pay unchanged
- exports remain byte/value stable after newer versions exist
- mixed-version exports report the version context
- exported entries cannot be silently edited/unapproved without the chosen
  correction behavior
- Xero preview/submission blocks or records the locked version context
- no runtime references to `pay_config_snapshots` remain after removal

Suggested commands:

```bash
bash ./bin/in-env regen-types
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Pay" --match "Payroll export parity" --match "Exports" --match "Xero"
```

## Fresh-Agent Prompt

> You are working in `/home/beau/documents/projects/ihp-roster`. Read root
> `AGENTS.md`, `docs/archive/plans/65-spec-agent-doc-alignment.md`, and
> `docs/archive/plans/68-append-only-pay-config-versioning.md`, then run `tk show ir-hw2v`
> and the child ticket you choose to implement.
>
> The product direction has pivoted: do not implement pay reproducibility by
> making `pay_config_snapshots.snapshot` JSON drive payroll. Replace the JSON
> snapshot system with append-only relational pay config versions and explicit
> approval/export/Xero locking gates. `ir-3vc6` and `ir-lz0x` are superseded as
> implementation direction and should be treated only as audit/problem context.
>
> Treat `Application/Schema.sql`, current controller/domain code, and tests as
> implementation truth, but update them toward the new design. The final state
> must remove `pay_config_snapshots`, `pay_config_snapshot_id`, and
> `payConfigSnapshotId` runtime usage rather than keeping JSON snapshots as a
> parallel source of truth.
>
> Start with `ir-vgdg` unless a prior agent has completed it: design the
> relational version schema and enumerate all pay-relevant mutable inputs used by
> `calculate_timesheet_pay`, payroll exports, and Xero submission. Then implement
> through `ir-srwi`, `ir-f7j7`, `ir-6s3f`, `ir-d1po`, and `ir-3qku`.
>
> Do not overwrite unrelated dirty work. Use `tk` for live status updates. After
> schema changes run `bash ./bin/in-env regen-types`, then
> `bash ./bin/in-env typecheck`. For behavioral changes run focused Hspec,
> especially `Pay`, `Payroll export parity`, `Exports`, and `Xero` matches.

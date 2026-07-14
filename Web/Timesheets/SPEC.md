# Timesheets Specification

This file describes implemented timesheet behavior. Future payroll and Xero
submission work belongs in `docs/workstreams/` until it lands.

## Canonical Terms

- A **Roster shift** is the current shift definition on a roster week.
- A **Timesheet suggestion** is a transient, server-derived view of an eligible
  roster shift. It is not a database row and is not a timesheet status.
- A **Timesheet entry** is the persisted work record used for review, approval,
  export, and payroll.
- Customer-facing suggestion cards use the badge **Rostered**.

## Current Contract

- Timesheet entries are venue-scoped and staff-scoped.
- Trial staff placeholders (`staff.user_id IS NULL`) are roster-only. They are
  excluded from timesheet selectors, manager filters, and suggestions; tampered
  create/update requests targeting them are rejected.
- Time inputs must be exact 15-minute increments.
- Timesheet start/end/break pickers use the venue-configured time-picker window.
  New ad-hoc entries default to the venue picker start time and an 8-hour end
  time clamped to the configured picker end when needed. Existing saved times
  outside the window remain valid and displayable.
- Each entry has one concrete worked date plus start/end/break data.
- Staff can manage their own visible entries. Managers can manage entries for
  linked active staff in their venue scope.

## Roster-Derived Suggestions

- Suggestions are derived on each Timesheets projection; no suggestion rows,
  statuses, delayed jobs, or grace periods exist.
- A roster shift is eligible when all of these are true:
  - its roster group is active and unarchived;
  - its roster week is live, including a future live week;
  - the slot is not soft-deleted;
  - staff, start time, valid end time, and shift type are present;
  - the staff member is linked and active;
  - the shift type is active; and
  - no active Timesheet entry has that `source_roster_slot_id`.
- Staff see suggestions only for themselves. Managers see suggestions in their
  normal Timesheets staff scope and filters. Filters are presentation state,
  not authorization; a manager retains action authority across their normal
  venue Timesheets scope even when a card is currently filtered out.
- **Show suggestions** is a URL-scoped filter, defaults on, and is preserved by
  Timesheets week navigation and mutation redirects. It is not persisted as a
  user preference.
- Suggestions use the same parameterized Timesheet card renderer as persisted
  entries, including fonts, hover behavior, time/break summary, and shape bar.
  Opacity and the Rostered badge identify the transient state. Create is shown
  in place of approval, and clicking the card body opens the prefilled form.

## Materialization And Ad-Hoc Entries

- Create snapshots the suggestion's current staff, date, shift type, times,
  automatic break, and immutable `source_roster_slot_id` into one unapproved
  Timesheet entry.
- Opening the suggestion card starts from the same snapshot. Staff/date/source
  stay locked while time, break, shift type, staff comment, and authorized
  manager note remain editable before creation.
- A roster-derived entry keeps its source staff, worked date, and source link on
  later edits. Later roster changes never update or delete the entry.
- Creation and approval are separate actions. There is no create-and-approve or
  bulk-create path.
- The day add control always creates an unrelated ad-hoc entry with no source
  link. If a suggestion exists for that day the form warns that it is separate,
  including when cards are hidden by Show suggestions; creation remains allowed
  and does not consume the suggestion.
- Active source identity is enforced by the partial unique index on
  `source_roster_slot_id` where `deleted_at IS NULL`. Materialization also
  serializes on the source roster slot and revalidates the projected source;
  concurrent duplicate submissions produce one active entry, while a changed
  or withdrawn source is rejected as stale.
- Soft-deleting a linked entry makes the suggestion eligible again. A later
  materialization creates a new snapshot while preserving the deleted history.
- Created entry versions record `source = roster_suggestion` and the roster slot
  id as provenance.

## Approval And History

- Approval writes keep status, actor, timestamp, and pay context consistent.
- Do not seed approved entries by setting only `isApproved`; fixtures must set
  all required approval fields together.
- Roster-derived materialization is always unapproved. Managers review and use
  the existing separate approval action.
- Payroll-adjacent changes preserve provenance through version/event helpers
  rather than destructive overwrite.

## Live Updates

- Server-rendered projection HTML remains authoritative.
- Timesheet entry mutations return HTMX fragments/OOB swaps to the actor and
  publish touched-resource invalidations for passive viewers.
- Publishing or returning a roster week to draft touches the corresponding
  Timesheet week resource. Roster-slot mutations also touch that resource, so
  mounted Timesheets viewers refetch authorized suggestion fragments.
- Week navigation and filters serialize through the closest
  `#timesheet-week-shell` with typed HTMX `replace` sync behavior.
- Date moves refresh both old and new entry fragments when both can be mounted.

## Retired Background Creation

- Publishing a roster never queues or creates Timesheet entries.
- The old venue toggle and onboarding control are absent and ignored by their
  legacy HTTP parameter.
- The compatibility database column remains non-destructively with value false.
- Deployment stops legacy job workers before applying the migration. Migration
  then forces the compatibility setting false and retires all active
  `roster_timesheet_creation` jobs. The new runtime safely completes any job
  claimed during startup as retired without creating an entry; historical
  completed jobs remain for audit.

## Extension Rules

- Xero submission uses approved, locked Timesheet facts; do not introduce a
  parallel payroll calculation path.
- Keep payroll correctness in Hspec/golden tests, not only browser tests.

## Verification

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Timesheets"
bash ./bin/in-env e2e e2e/live-fragment-multiview.spec.ts
```

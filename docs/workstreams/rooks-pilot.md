# Rooks Pilot Readiness

Status: active

GitHub issues:

- `#43` - parent epic
- `#119` - staff-level Xero custom pay item overrides
- `#52` - roster-derived Timesheet suggestions

Living docs to update:

- `Web/RosterWeeks/SPEC.md`
- `Web/Timesheets/SPEC.md`
- `Web/LeaveRequests/SPEC.md`
- `Application/Xero/SPEC.md`
- `specs/02-domain-model.md`
- `specs/03-access-control-and-auth.md`
- `specs/09-testing-and-acceptance.md`

Archived context:

- `docs/archive/plans/70-rooks-pilot-requirements.md`

## Goal

Prepare the first Rooks trial without broadening Bepis into a sensitive
employee-onboarding store.

Pilot dates:

- first roster/pay week starts 2026-06-08
- first Xero submission target is 2026-06-15

Roster, timesheet, Xero, and RSA acceptance are pilot-critical. Google Form
onboarding remains deferred pending legal/product review.

## Current State

Lower-risk pilot slices have landed for availability language, typed user
preferences, Timesheet filtering/cards/comments, roster end-time/shift-type
foundations, and explicit roster-derived Timesheet suggestions. Delayed automatic
Timesheet creation is retired. The remaining pilot-critical gaps are tracked in
the linked issues, including RSA, roster wage prediction follow-up, and Xero
custom pay item overrides.

## Intended Contract

### Roster scheduling

- End times are venue opt-in.
- Draft roster slots may be incomplete.
- A roster cannot go live when a staffed shift is missing start time, end time,
  or shift type.
- Unstaffed slots do not require shift type.
- Overnight shifts are valid; an end time earlier than start time means the
  end datetime is on the following day.
- Shift types are explicit roster-slot assignments, not note/flag text.

### Predicted roster wages

- Admin-and-up users can view per-day and week predicted wage totals from the
  roster context.
- Predictions use rostered staff, shift type, concrete start/end datetimes, and
  current pay rules.
- V1 assumes a 30-minute unpaid break for shifts over 6 hours.
- Predictions are not final payroll and must not be presented as Xero output.

### Roster-derived Timesheet suggestions

- Complete linked-staff shifts on live rosters appear immediately as transient
  Rostered cards in Timesheets, including future weeks.
- Staff create their own entries explicitly; managers can create entries within
  their normal Timesheets staff scope.
- Quick Create or opening the Rostered card and saving its prefilled form
  produces an unapproved snapshot with immutable roster-source provenance.
  Approval remains a separate manager action.
- Ad-hoc entries remain allowed and do not consume a suggestion.
- Returning a roster to draft hides unmaterialized suggestions. Later roster
  edits never mutate an already-created Timesheet entry.
- No venue opt-in, grace period, background creation job, bulk create, or
  create-and-approve behavior exists.

### Xero custom pay item overrides

- Synced Xero earnings-rate pay items can be selected as staff-level overrides.
- The Rooks owner-pay case collapses all generated Xero timesheet lines for the
  owner staff member to the selected pay item.
- Ordinary staff continue using managed pay item mappings.
- Dropdown labels should show human-readable Xero name before account code
  metadata.

### RSA compliance

- Staff can upload their own RSA document.
- Managers/admins can upload RSA documents for staff.
- Store the document and metadata, with expiry date required.
- Notify 30 days before expiry by email and in-app notification.
- Managers/admins can see missing, expiring, and expired RSA state.

## Boundaries

Bepis must not store TFN, bank, super, or equivalent sensitive onboarding data
for this pilot. Do not add Google OAuth access for form creation or response
reads as part of this stream.

## Exit Criteria

- Pilot-critical tickets are closed or moved to a successor workstream.
- Current roster/timesheet/Xero/RSA behavior is captured in living subsystem
  specs.
- First-client acceptance coverage links to the relevant Hspec/E2E tests.

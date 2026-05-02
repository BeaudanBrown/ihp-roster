# Rooks Pilot Readiness

Status: active

Tickets:

- `ir-9jap` - parent epic
- `ir-2rko` - RSA document acceptance and expiry tracking
- `ir-7xks` - auto-create pending timesheets from live rosters
- `ir-ptny` - admin-only predicted roster wage totals
- `ir-z87w` - staff-level Xero custom pay item overrides

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

Lower-risk pilot slices have already landed for availability language, typed
user preferences, timesheet staff filtering/clickable cards/comments, and
roster end-time/shift-type foundations. The open pilot-critical gaps are RSA
document handling, roster wage prediction, live-roster-to-timesheet automation,
and Xero custom pay item overrides.

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

### Roster-to-timesheet automation

- Automation is venue opt-in.
- Only live rosters participate.
- Pending timesheets are created 2 hours after the actual shift end datetime.
- Auto-created entries are pending, never auto-approved.
- Later roster edits do not mutate already-created timesheets; the actor should
  see a warning or toast.

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

# Pipeline 70 - Rooks Pilot Requirements

Read after `IMPLEMENTATION_PLAN.md`, `docs/archive/plans/20-roster-and-conflicts.md`,
`docs/archive/plans/30-timesheets-and-leave.md`, `docs/archive/plans/57-xero-payroll-integration.md`,
and `docs/archive/plans/50-release-readiness.md`.

## Goal

Capture the first Rooks trial requirements as implementation-ready product
decisions and route them into repo-local `tk` tickets.

The pilot target is:

- first roster/pay week starts 2026-06-08
- first Xero submission target is 2026-06-15
- Roster, timesheet, Xero, and RSA acceptance are pilot-critical.
- Google Form onboarding is intentionally deferred while legal/product shape is
  investigated.

Live implementation tracking lives under the `ir-9jap` ticket epic and its
children.

## Decisions

### Roster scheduling contract

- End times are venue opt-in.
- If end times are enabled, incomplete staffed roster slots can exist in draft.
- A roster cannot go live when any staffed shift is missing start time, end
  time, or shift type.
- Unstaffed slots do not require shift type.
- End times are visible to all users.
- Overnight shifts are valid. When end time is earlier than start time, treat
  the end datetime as the following day.
- Replace the roster `Flag`/note-as-shift-type pattern with explicit shift type
  assignment.
- Shift type selection should be inline on the roster slot.
- Shift types are work roles/areas such as `manager`, `glassy`, and `bar`.

Ticket: `ir-rob3`

### Predicted roster wages

- Predicted wages should be accessible from the roster page.
- V1 output is per-day totals and week total only.
- Wage totals are visible to admin-and-up users only.
- Predictions use rostered staff, shift type, and concrete start/end datetimes.
- Predictions assume a 30-minute unpaid break inside shifts over 6 hours.
- Predictions are not final payroll.

Ticket: `ir-ptny`

### Roster-to-timesheet automation

- Auto-creation is venue opt-in.
- Only live rosters participate.
- Pending timesheets are created 2 hours after the actual shift end datetime.
- Overnight shifts use the calculated next-day end datetime.
- Auto-created timesheets are pending, never auto-approved.
- Later roster edits do not mutate already-created timesheets. Surface a warning
  or toast instead.

Ticket: `ir-7xks`

### Timesheet UX and comments

- Manager timesheet page needs staff filtering.
- Timesheet cards should open the edit dialog directly.
- Staff comments are edited only by the owning staff member in the timesheet
  edit dialog.
- Managers/admins can view staff comments.
- Managers/admins get one manager-only internal note field.
- Staff comment edits after approval do not create a special post-approval
  state.

Ticket: `ir-gsx1`

### Xero custom pay item overrides

- Imported/synced Xero earnings-rate pay items can be selected as staff-level
  overrides.
- The Rooks owner-pay case uses one custom Xero pay item for owner staff.
- Owner override collapses all generated Xero timesheet lines for that staff
  member to the selected custom pay item.
- Ordinary staff continue using managed pay item mappings.
- Xero pay item dropdown labels should show the human-readable name first, then
  account code metadata.
- Bepis does not calculate tax; Xero remains the payroll/tax/STP authority.

Ticket: `ir-z87w`

### Availability language

- Formal paid leave is absent from the pilot.
- Existing unavailability behavior stays in place.
- Staff-facing `leave request` language should become Availability /
  Unavailable period / Add unavailable time.

Ticket: `ir-bt06`

### RSA compliance

- RSA document acceptance is pilot-critical.
- Staff can upload their own RSA document.
- Managers/admins can upload RSA documents for staff.
- Store the uploaded document plus metadata, with expiry date as the minimum
  required metadata.
- Notify 30 days before expiry by email and in-app notification.
- Show missing, expiring, and expired RSA status to managers/admins.
- TFN, bank, super, and other serious onboarding data are explicitly out of
  scope for Bepis storage.

Ticket: `ir-2rko`

### User preferences

- Add a proper typed per-user preferences table.
- Do not use a generic JSON dumping-ground table.
- First preference is global roster layout mode.
- The day-column roster layout preference persists globally between sessions.
- Leave room for future explicit preferences such as selected roster group,
  density, hidden panels, and default roster view.

Ticket: `ir-jz1z`

## Deferred Research

### Onboarding and sensitive data

The desired direction is for venue staff to send TFN, bank, super, and similar
data directly to the venue owner without Bepis handling it.

For now:

- do not store TFN, bank, super, or equivalent serious data in Bepis
- do not add Google OAuth access for form creation or response reads
- defer Google Form onboarding until legal/product risk is better understood
- the lower-risk future shape is likely a venue-provided Google Form URL that
  redirects to Bepis account creation after submission


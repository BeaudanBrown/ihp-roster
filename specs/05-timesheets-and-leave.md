# Timesheets and Leave

## Timesheet entry rules

- Start/end/break inputs use exact **15-minute increments** by default. A venue may enable whole-minute precision for all four boundaries.
- Non-conforming inputs are rejected with explicit validation errors.
- Shift duration caps and sanity checks apply (e.g. max duration, break <= shift duration).
- Fifteen-minute mode reuses the shared modal picker. Minute-precision mode uses an inline native time input, while both persist canonical local wall-clock values as `HH:MM`.

## Roster-derived Timesheet prefill

- Clicking a Timesheet day's `+` loads a grouped chooser of authorized blank
  choices and complete eligible shifts from active Published roster groups,
  including future shifts. Current Staff/group presentation filters do not hide
  authorized shift candidates.
- Prefill candidates are transient values, not stored rows or statuses. Returning
  the roster to Draft removes its shifts from the chooser; no elapsed grace period
  creates an entry.
- Staff see only their shifts. Management sees shifts within normal Timesheet
  Staff authority. A roster shift always requires explicit chooser selection;
  only one blank choice with no shifts may open its form directly.
- Save snapshots current values into one unapproved **Timesheet entry** and
  records immutable roster-slot provenance. Time, break, shift type, and
  authorized comments may change before creation. Managers may correct Staff
  only within the immutable source group while worked date and source stay fixed.
- Approval remains a separate manager action. Ad-hoc entries remain valid,
  unlinked, and do not consume a similar roster shift.
- One active linked entry per roster slot is enforced under concurrent requests.
  Soft-deleting it restores the candidate without deleting history.

## Timesheet edit windows

- Staff edits are restricted to configured operational window.
- Managers, Venue Admins and Venue Owners may bypass staff window restrictions.

## Approval state machine

- Initial state: unapproved.
- Manager, Venue Admin or Venue Owner can approve.
- If staff edits an approved entry, entry automatically resets to unapproved.
- Once a timesheet is in business use, corrections must be additive or versioned rather than silent destructive overwrite.
- Approval, unapproval and correction actions must preserve actor attribution and timestamps.
- Approval binds the timesheet to the pay/config snapshot version used for the calculation.

## Leave lifecycle

- Staff submits leave request (`pending`).
- Venue Admin, Venue Owner or other authorized reviewer approves or denies.
- Validation: `end_date >= start_date`.
- Leave status changes must create attributable history rather than replacing prior state with no record.
- Destructive deletion is not the normal lifecycle for leave that has already been reviewed or relied on operationally.

## Leave and roster integration

- On leave approval, roster conflict signals for affected date range must be recalculated.
- Leave approval, denial and correction actions should be auditable in the same transaction where feasible.

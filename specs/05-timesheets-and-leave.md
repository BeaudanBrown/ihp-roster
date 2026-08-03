# Timesheets and Leave

## Timesheet entry rules

- Start/end/break inputs use exact **15-minute increments** by default. A venue may enable whole-minute precision for all four boundaries.
- Non-conforming inputs are rejected with explicit validation errors.
- Shift duration caps and sanity checks apply (e.g. max duration, break <= shift duration).
- Fifteen-minute mode reuses the shared modal picker. Minute-precision mode uses an inline native time input, while both persist canonical local wall-clock values as `HH:MM`.

## Roster-derived Timesheet suggestions

- Complete eligible shifts on active live rosters are derived immediately as
  transient **Timesheet suggestions**, including future shifts.
- Suggestions are not stored rows or statuses. Returning the roster to draft
  hides them; no elapsed grace period may create an entry.
- Staff may create their own suggestion. Managers may create suggestions within
  their normal Timesheet staff scope.
- Create snapshots current values into one unapproved **Timesheet entry** and
  records immutable roster-slot provenance. Clicking the highlighted suggestion
  card opens the same prefilled form shape as an entry; time, break, shift type,
  and authorized comments may change before creation. After creation, managers
  may correct staff assignment while the worked date and source link stay fixed.
- Approval remains a separate manager action.
- Ad-hoc entries remain valid, unlinked, and do not consume a suggestion.
- One active linked entry per roster slot is enforced under concurrent requests.
  Soft-deleting it restores the suggestion without deleting history.

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

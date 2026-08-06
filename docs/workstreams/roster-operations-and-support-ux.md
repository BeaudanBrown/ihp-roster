# Shared Side-Panel Closeout

This workstream retains the unresolved SidePanel lane from the broader
roster/support UX program. Implemented roster notification, Open-shift,
template, Timesheet-suggestion, and support-impersonation contracts live in
subsystem specs, ADRs, and code. GitHub owns status and dependency ordering.

## Issues

- [#316](https://github.com/BeaudanBrown/ihp-roster/issues/316) — epic.
- [#322](https://github.com/BeaudanBrown/ihp-roster/issues/322) — cross-page
  acceptance and legacy cleanup.

## Intended Contract

- A generated SidePanel capability owns only mechanical layout, toggle, tabs,
  accessibility, responsiveness, and HTMX reconciliation.
- Roster, Timesheets, and manager Unavailability retain feature-owned content,
  actions, resources, state, and authorization.
- Visibility is transient. Valid tab state survives in-mount replacement and
  resets on full navigation.
- Final acceptance must prove consistent header placement, phone/desktop layout,
  focus/Escape behavior, nested/live reconciliation, and no horizontal overflow
  before legacy CSS/JS/URL mechanics are removed.
- Admin, Xero, Billing, Profile, and Support are outside this migration.

## Affected Living Docs

- `Web/RosterWeeks/README.md`, `Web/RosterWeeks/SPEC.md`, and
  `Web/RosterWeeks/AGENTS.md`.
- `Web/Timesheets/README.md`, `Web/Timesheets/SPEC.md`, and
  `Web/Timesheets/AGENTS.md`.
- `Web/LeaveRequests/README.md`, `Web/LeaveRequests/SPEC.md`, and
  `Web/LeaveRequests/AGENTS.md`.
- Shared frontend contract/interaction docs when the generic capability changes.

## Exit Criteria

- #322 closes with required responsive/live, accessibility, and deterministic
  test evidence.
- Implemented contracts are reflected in living docs and Page Help.
- No unresolved design remains here; then delete this workstream.

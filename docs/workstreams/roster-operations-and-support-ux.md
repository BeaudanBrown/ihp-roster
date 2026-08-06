# Roster Notifications And Side-Panel Closeout

This workstream retains the two unresolved lanes from the broader roster/support
UX program. Implemented Open-shift, template, Timesheet-suggestion, and support-
impersonation contracts now live in subsystem specs, ADRs, and code. GitHub owns
status and dependency ordering.

## Email Live Rosters

Issues:

- [#312](https://github.com/BeaudanBrown/ihp-roster/issues/312) — epic.
- [#314](https://github.com/BeaudanBrown/ihp-roster/issues/314) — confirmation
  and latest-run UI.
- [#315](https://github.com/BeaudanBrown/ihp-roster/issues/315) — delivery,
  privacy, convergence, and documentation acceptance.

### Intended Contract

- A roster editor deliberately emails one live roster-group week; publication
  never sends automatically.
- One immutable run snapshots the venue/group/week, roster content, and eligible
  recipients. Existing AppJobs own per-recipient retries and delivery.
- Each recipient sees only their own assigned shifts, all Open shifts, and the
  authenticated roster link—never another person's assigned schedule.
- Trial, unlinked, inactive, or email-less staff are skipped. A confirmed run
  continues if the roster later returns to draft.
- Active runs deduplicate. Terminal runs may be deliberately repeated without a
  roster-change heuristic or proactive “Resend” workflow.
- UI exposes bounded aggregate status and sanitized failures only; delivery
  errors never block publication.
- Actual/effective actor attribution remains truthful during support
  impersonation.

## Shared Side Panels

Issues:

- [#316](https://github.com/BeaudanBrown/ihp-roster/issues/316) — epic.
- [#322](https://github.com/BeaudanBrown/ihp-roster/issues/322) — cross-page
  acceptance and legacy cleanup.

### Intended Contract

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
- `Application/Helper/View/PageHelp.hs`.
- Shared frontend contract/interaction docs when the generic capability changes.

## Exit Criteria

- #314, #315, and #322 close with required mail, security, responsive/live,
  accessibility, and deterministic test evidence.
- Implemented contracts are reflected in living docs and Page Help.
- No unresolved design remains here; then delete this workstream.

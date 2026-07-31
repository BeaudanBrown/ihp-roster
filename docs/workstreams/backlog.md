# Backlog And Smaller Feature Streams

Status: active

This file routes open epics that do not yet need a dedicated workstream file.
Promote any section here into its own workstream when design detail grows beyond
a few paragraphs.

## Staff Profiles And Preferences

GitHub issues:

- `#19`
- `#7`
- `#88`
- `#68`
- `#120`

Living docs to update:

- `Web/RosterWeeks/SPEC.md`
- `Web/LeaveRequests/SPEC.md`
- future profile/staff local docs when added

Direction:

- Keep staff profile data venue-scoped.
- Keep roster preferences typed and queryable; do not use generic JSON dumping
  grounds for core scheduling facts.
- Do not add sensitive onboarding data without a separate product/compliance
  spec.

## Support Access

GitHub issues:

- `#95`
- `#22`
- `#102`
- `#1`
- `#26`

Living docs to update:

- `specs/03-access-control-and-auth.md`
- root `AGENTS.md`
- support controller/view docs if the surface grows

Direction:

- Founder support access is platform-level and distinct from venue membership.
- Support-mode UI and audit should make the access mode explicit.
- Consider defense-in-depth that makes the super-admin login/support surface
  reachable only from a trusted host or founder tailnet before credentials can
  even be submitted.
- Ordinary multi-venue switching remains separate from support access.

## Public Holidays

GitHub issues:

- `#23`
- `#82`

Living docs to update:

- `specs/02-domain-model.md`
- `specs/06-pay-engine.md`
- application docs near `Application/PublicHolidays/` if the subsystem grows

Direction:

- Regional Victorian public holiday applicability must be explicit.
- Recurring refreshes should use the app job/timer pattern.
- Pay calculations must use the accepted holiday applicability that matches the
  payroll period.

## Demo And Profile Seeding

GitHub issues:

- `#298`
- `#300`

Living docs to update:

- `Application/Script/` docs if added
- `Test/AGENTS.md`
- `e2e/AGENTS.md`

Direction:

- Keep exact parity fixtures deterministic and small.
- Keep manual dev/profile seeds richer but generated through named scenarios.
- Keep `Application.Fixture.DevFixtures` as the thin interpreter; domain projections live in its `Staff`, `Roster`, `Leave`, and `Payroll` modules.
- Do not weaken test fixture determinism to make manual exploration easier.

## Week Controls

Living docs to update:

- `Web/RosterWeeks/SPEC.md`
- `Web/Timesheets/SPEC.md`
- shared week/path helper docs if extracted

Direction:

- Keep week navigation URL-driven.
- Promote shared controls only where roster and timesheets genuinely share
  behavior.

## Later Backlog

GitHub issues:

- `#87` - ordinary account multi-venue switching
- `#111` - multi-group payroll exports

Direction:

- Treat these as later product lanes. Do not let first-client or Rooks pilot
  work accidentally depend on them.

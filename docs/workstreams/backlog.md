# Backlog And Smaller Feature Streams

Status: active

This file routes open epics that do not yet need a dedicated workstream file.
Promote any section here into its own workstream when design detail grows beyond
a few paragraphs.

## Staff Profiles And Preferences

Tickets:

- `ir-45b6`
- `ir-l2l8`
- `ir-2d9a`
- `ir-n0fe`
- `ir-iw4k`
- `ir-zl1t`

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

Tickets:

- `ir-qi7t`
- `ir-4ggo`
- `ir-sy25`
- `ir-00br`

Living docs to update:

- `specs/03-access-control-and-auth.md`
- root `AGENTS.md`
- support controller/view docs if the surface grows

Direction:

- Founder support access is platform-level and distinct from venue membership.
- Support-mode UI and audit should make the access mode explicit.
- Ordinary multi-venue switching remains separate from support access.

## Public Holidays

Tickets:

- `ir-52nw`
- `ir-mhfj`
- `ir-kt2x`

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

Tickets:

- `ir-hsuu`
- `ir-v5ed`
- `ir-fao4`
- `ir-3wcl`

Living docs to update:

- `Application/Script/` docs if added
- `Test/AGENTS.md`
- `e2e/AGENTS.md`

Direction:

- Keep exact parity fixtures deterministic and small.
- Keep manual dev/profile seeds richer but generated through named scenarios.
- Do not weaken test fixture determinism to make manual exploration easier.

## Surface Projection Cache

Tickets:

- `ir-jooi`
- `ir-vutq`
- `ir-53mu`

Living docs to update:

- `Application/Helper/LiveUpdate.SPEC.md`
- feature-local specs using projection-backed fragments

Direction:

- Projection caches should support live and HTMX surfaces without changing
  canonical authorization or source-of-truth rendering.
- Add verification before making projection cache behavior relied upon by
  high-frequency surfaces.

## Week Controls

Tickets:

- `ir-5o6t`
- `ir-w8dk`
- `ir-y8mj`

Living docs to update:

- `Web/RosterWeeks/SPEC.md`
- `Web/Timesheets/SPEC.md`
- shared week/path helper docs if extracted

Direction:

- Keep week navigation URL-driven.
- Promote shared controls only where roster and timesheets genuinely share
  behavior.

## Later Backlog

Tickets:

- `ir-mwhc` - ordinary account multi-venue switching
- `ir-vifu` - multi-group payroll exports

Direction:

- Treat these as later product lanes. Do not let first-client or Rooks pilot
  work accidentally depend on them.

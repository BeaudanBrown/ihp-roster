# Implementation Routing

This file is the global routing index for implementation order. It is not a
live checklist and it no longer owns detailed pipeline plans.

Use:

- `.tickets/` through `tk` for live status, dependencies, and next actions.
- `docs/workstreams/` for proposed or active feature-stream design.
- subsystem-local `README.md`, `SPEC.md`, and `AGENTS.md` for implemented
  behavior and local editing rules.
- `docs/archive/plans/` for historical numbered plans.

## Current Direction

The current implementation direction is:

- local, founder-managed rollout
- small number of venues
- standardized managed SaaS with venue as the current customer boundary
- no public self-serve venue creation in the near term

High-priority product and architecture decisions:

- business authority comes from `venue_memberships`, not `users`
- privileged access uses founder-managed venue bootstrap, not bootstrap-admin
  signup
- platform support capability is separate from venue business roles
- support access reuses the real current venue while keeping
  `currentVenueMembership` absent
- payroll-adjacent records use correction-safe history
- pay/config history is moving to append-only relational version rows
- roster scheduling is moving toward explicit roster groups
- venue bootstrap should converge on one idempotent minimum-roster path
- the first Rooks pilot requires roster end times, explicit shift types,
  admin-only predicted wage totals, live-roster-to-pending-timesheet automation,
  staff-level Xero custom pay item overrides, availability language, RSA
  document acceptance, and typed user preferences
- Bepis should not store TFN, bank, super, or equivalent sensitive onboarding
  data

## Active Workstream Map

| Workstream | Primary tickets | Routing |
| --- | --- | --- |
| Rooks pilot readiness | `ir-9jap`, `ir-2rko`, `ir-7xks`, `ir-ptny`, `ir-z87w` | `docs/workstreams/rooks-pilot.md` |
| Pay config versioning | `ir-hw2v` and children | `docs/workstreams/pay-config-versioning.md` |
| Xero payroll integration | `ir-176p`, `ir-mjov` and children | `docs/workstreams/xero-payroll.md` |
| Roster groups and bootstrap | `ir-t7be` and children | `docs/workstreams/roster-groups.md` |
| Record retention | `ir-u4mc` and children | `docs/workstreams/record-retention.md` |
| Release readiness | `ir-g778` and children | `docs/workstreams/release-readiness.md` |
| Schema hardening | `ir-caf4` and children | `docs/workstreams/schema-hardening.md` |
| Maintenance and boundaries | `ir-m8hc`, `ir-6vvh`, `ir-18tm`, `ir-9f7z`, `ir-2usx` | `docs/workstreams/maintenance.md` |
| Backlog and smaller streams | `ir-45b6`, `ir-qi7t`, `ir-52nw`, `ir-hsuu`, `ir-jooi`, `ir-5o6t` | `docs/workstreams/backlog.md` |

## Global Order

Use ticket dependencies for exact blocking relationships. At the portfolio
level, prefer this order:

1. Venue-scoped authority, support access, and bootstrap foundations.
2. Schema hardening and retention guardrails that protect future customer data.
3. Pay config versioning and payroll reproducibility.
4. Rooks pilot-critical roster/timesheet/RSA/Xero gaps.
5. Xero Payroll AU submission on top of approved, locked payroll facts.
6. Roster groups and multi-group expansion where it does not destabilize the
   pilot.
7. Release readiness and first-client acceptance sweeps.
8. Maintenance refactors in slices that do not collide with active feature work.

## How To Start Work

1. Run `tk ready` or inspect the target ticket with `tk show <id>`.
2. Read the relevant workstream in `docs/workstreams/` if the behavior is not
   fully implemented.
3. Read the local subsystem docs beside the code you will touch.
4. Use archived numbered plans only when linked by the ticket/workstream.
5. As behavior lands, update local `SPEC.md`/`AGENTS.md` before closing the
   ticket or retiring the workstream.

## Historical Plans

The old numbered plan files were moved to `docs/archive/plans/`. They are
retained for context and supersession history, but they are not current status
or implementation authority.

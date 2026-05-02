# Compliance Engineering Routing

This file maps compliance-driven engineering concerns to the current ticket and
workstream system. It is not a standalone implementation checklist.

## Source Of Truth

- Live work status: `.tickets/`
- Future feature streams: `docs/workstreams/`
- Implemented subsystem behavior: local `SPEC.md` files beside code
- Compliance/product obligations: this `specs/10-au-saas-security-privacy-compliance/`
  directory
- Historical implementation plans: `docs/archive/plans/`

## Current Routing

| Concern | Current route |
| --- | --- |
| Membership-scoped authority and venue boundary | implemented foundation; see `specs/03-access-control-and-auth.md` and root `AGENTS.md` |
| Support access and audit distinction | `ir-qi7t`, `ir-sy25` |
| Record retention and protected deletion | `docs/workstreams/record-retention.md`, `ir-u4mc` |
| Pay/config historical reproducibility | `docs/workstreams/pay-config-versioning.md`, local export/timesheet/Xero specs |
| Export governance | `Application/Helper/Export/SPEC.md`, `ir-g778` for release acceptance |
| Xero payroll integration controls | `docs/workstreams/xero-payroll.md`, `Application/Xero/SPEC.md` |
| First-client readiness | `docs/workstreams/release-readiness.md`, `ir-g778`, `ir-yo89` |
| Rooks pilot compliance gaps | `docs/workstreams/rooks-pilot.md`, especially `ir-2rko` for RSA |
| Security/session/header hardening | `ir-2ds0`, `docs/workstreams/release-readiness.md` |

## Compliance Invariants

- Venue is the current customer boundary.
- `users` is identity; `venue_memberships` owns venue business roles.
- Founder support access must be explicit and auditable.
- Payroll-adjacent records must be correction-safe and historically
  reproducible.
- Export generation and download must be scoped, auditable, and expiry-aware.
- Sensitive data such as TFN, bank, super, health, biometrics, or government
  identifiers requires a dedicated product/compliance spec before storage.
- Bepis must not add sensitive onboarding-data storage as part of the Rooks
  pilot.

## When Adding Compliance Work

1. Create or update a `tk` ticket.
2. If the behavior is not implemented, add it to a `docs/workstreams/` file.
3. If it becomes implemented, update the local subsystem `SPEC.md`.
4. If it changes a durable architecture decision, add or supersede an ADR.
5. Keep this file as a routing map, not a task list.

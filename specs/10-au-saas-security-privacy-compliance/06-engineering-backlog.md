# Compliance Engineering Routing

This file maps compliance-driven engineering concerns to the current ticket and
workstream system. It is not a standalone implementation checklist.

## Source Of Truth

- Live work status: GitHub Issues
- Future feature streams: `docs/workstreams/`
- Implemented subsystem behavior: local `SPEC.md` files beside code
- Compliance/product obligations: this `specs/10-au-saas-security-privacy-compliance/`
  directory
- Historical implementation plans: `docs/archive/plans/`

## Current Routing

| Concern | Current route |
| --- | --- |
| Membership-scoped authority and venue boundary | implemented foundation; see `specs/03-access-control-and-auth.md` and root `AGENTS.md` |
| Support access and audit distinction | `#95`, `specs/03-access-control-and-auth.md` |
| Record retention and protected deletion | `docs/workstreams/record-retention.md`, `#106` |
| Pay/config historical reproducibility | local export, Timesheet, Xero, and pay-engine specs |
| Export governance | `Application/Helper/Export/SPEC.md`, `#60` for release acceptance |
| Xero payroll integration controls | `Application/Xero/SPEC.md` |
| Subscription billing controls | `Application/Billing/SPEC.md`, `Application/Billing/RUNBOOK.md` |
| First-client readiness | `docs/workstreams/release-readiness.md`, `#60`, `#116` |
| Security/session/header hardening | `#8`, `docs/workstreams/release-readiness.md` |

## Compliance Invariants

- Venue is the current customer boundary.
- `users` is identity; `venue_memberships` owns venue business roles.
- Founder support access must be explicit and auditable.
- Payroll-adjacent records must be correction-safe and historically
  reproducible.
- Export generation and download must be scoped, auditable, and expiry-aware.
- Sensitive data such as TFN, bank, super, health, biometrics, or government
  identifiers requires a dedicated product/compliance spec before storage.
- Billing uses hosted Stripe surfaces. The app must not store card details,
  bank payment details, ABNs, tax IDs, billing addresses or full raw Stripe
  payloads by default.
- Bepis must not add sensitive onboarding-data storage as part of the Rooks
  pilot.

## When Adding Compliance Work

1. Create or update a GitHub issue.
2. If the behavior is not implemented, add it to a `docs/workstreams/` file.
3. If it becomes implemented, update the local subsystem `SPEC.md`.
4. If it changes a durable architecture decision, add or supersede an ADR.
5. Keep this file as a routing map, not a task list.

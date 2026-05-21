# Workstreams

Workstreams are for feature streams that are proposed, active, blocked, or only
partly implemented. They replace the old numbered `plans/` files as the place
for forward-looking design.

## Rules

- Every workstream must link to one or more `tk` tickets.
- Workstreams describe intent, scope, constraints, and integration points.
- Workstreams are not the source of truth for implemented behavior.
- Every workstream must list the living docs that need updates as it lands.
- When a slice lands, update the relevant subsystem `SPEC.md` or `AGENTS.md`.
- When no future work remains, move durable decisions into ADRs or specs and
  archive the workstream.

## Status Values

- `proposed`: product or architecture direction exists, but implementation is
  not ready to start.
- `active`: implementation is underway through `tk`.
- `blocked`: waiting on a named dependency.
- `implemented`: the workstream is complete and should be archived after docs
  are reconciled.
- `superseded`: replaced by another workstream or ADR.

## Tracked Workstreams

- `rooks-pilot.md` - Rooks pilot readiness.
- `pay-config-versioning.md` - append-only pay config versioning.
- `xero-payroll.md` - Xero Payroll AU integration.
- `roster-groups.md` - roster groups and bootstrap defaults.
- `record-retention.md` - soft deletion and retention guardrails.
- `release-readiness.md` - first-client release readiness.
- `schema-hardening.md` - V1 schema hardening.
- `subscription-billing.md` - per-venue Stripe Billing subscriptions.
- `maintenance.md` - cross-cutting refactors and doc/agent cleanup.
- `live-surface-architecture.md` - typed live-fragment surface ergonomics and
  robustness.
- `strict-live-surface-overhaul.md` - removal of the old live-surface
  compatibility/manual authoring layer and strict typed migration.
- `live-update-runtime-simplification.md` - follow-up cleanup of internal
  live-update compatibility primitives and protocol simplification decisions.
- `roster-sql-read-model-trial.md` - trial replacing roster projection-cache
  reads with a direct SQL/database-near read model.
- `backlog.md` - smaller open streams that do not yet need dedicated files.

## Workstream Exit Criteria

A workstream can leave `active` only when:

- linked tickets are closed or the remaining work has moved to another
  workstream
- implemented behavior is described in local `SPEC.md` files
- reusable implementation rules are in local `AGENTS.md` files
- significant decisions are captured in ADRs
- old plan context is linked from `docs/archive/` if still useful

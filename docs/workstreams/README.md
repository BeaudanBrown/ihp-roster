# Workstreams

Workstreams are for feature streams that are proposed, active, blocked, or only
partly implemented. They replace the old numbered `plans/` files as the place
for forward-looking design.

## Rules

- Every workstream must link to one or more GitHub issues.
- Workstreams describe intent, scope, constraints, and integration points.
- Workstreams are not the source of truth for implemented behavior.
- Every workstream must list the living docs that need updates as it lands.
- When a slice lands, update the relevant subsystem `SPEC.md` or `AGENTS.md`.
- When no future work remains, move durable decisions into ADRs or specs and
  archive the workstream.

## Status Values

- `proposed`: product or architecture direction exists, but implementation is
  not ready to start.
- `active`: implementation is underway through GitHub Issues.
- `blocked`: waiting on a named dependency.
- `implemented`: the workstream is complete and should be archived after docs
  are reconciled.
- `superseded`: replaced by another workstream or ADR.

## Tracked Workstreams

- `rooks-pilot.md` - Rooks pilot readiness.
- `pay-config-versioning.md` - append-only pay config versioning.
- `explicit-roster-pay-disposition.md` - explicit staff/shift pay modes and roster-only behavior.
- `hospitality-award-wage-compliance.md` - MA000009 wage-engine certification and cutover.
- `xero-payroll.md` - Xero Payroll AU integration.
- `roster-groups.md` - roster groups and bootstrap defaults.
- `record-retention.md` - soft deletion and retention guardrails.
- `release-readiness.md` - first-client release readiness.
- `schema-hardening.md` - V1 schema hardening.
- `subscription-billing.md` - per-venue Stripe Billing subscriptions.
- `maintenance.md` - cross-cutting refactors and doc/agent cleanup.
- `bepis-component-pipelines.md` - typed Bepis component pipelines for action
  contracts, mutations, scope/audit/realtime evidence, and generated facts.
- `bepis-effect-evidence-finalization.md` - final no-legacy Bepis runtime fact
  model where actual effect helpers emit typed facts and telemetry.
- `opentelemetry-observability.md` - OpenTelemetry traces, agent profile
  artifacts, production trace/log capture, and tailnet Grafana viewing.
- `backlog.md` - smaller open streams that do not yet need dedicated files.

## Workstream Exit Criteria

A workstream can leave `active` only when:

- linked issues are closed or the remaining work has moved to another
  workstream
- implemented behavior is described in local `SPEC.md` files
- reusable implementation rules are in local `AGENTS.md` files
- significant decisions are captured in ADRs
- old plan context is linked from `docs/archive/` if still useful

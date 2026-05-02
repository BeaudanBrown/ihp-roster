# V1 Schema Hardening

Status: active

Tickets:

- `ir-caf4` - parent epic
- `ir-7gm0`, `ir-iz2g`, `ir-jra6`, related children

Living docs to update:

- `Application/AGENTS.md`
- `specs/02-domain-model.md`
- `specs/05-timesheets-and-leave.md`
- `specs/06-pay-engine.md`
- feature-local `SPEC.md` files touched by schema constraints

Archived context:

- `docs/archive/plans/60-v1-schema-hardening.md`

## Goal

Add durable schema constraints, tenant integrity, indexes, and statistics before
customer data depends on weak application-only invariants.

## Current State

Schema work must respect IHP parser quirks around enums and rewritten check
constraints. Root and application agent docs record the current safe patterns.

## Intended Contract

- Tenant and venue ownership should be explicit at the schema level where
  possible.
- Required text/enum/status fields should have parser-safe constraints.
- Historical and payroll-adjacent records should preserve lineage.
- Schema changes must regenerate types, apply to the dev DB, and pass startup
  verification when enums or constraints change.

## Exit Criteria

- Core constraints and nullable uniqueness fixes land with tests.
- Living schema guidance in `Application/AGENTS.md` stays aligned with the
  final constraint patterns.

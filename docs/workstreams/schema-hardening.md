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
Bepis is now live, so the migration requirement from the archived V1 hardening
plan is promoted into active guidance: schema changes must preserve existing
customer data and include an IHP migration path for deployed databases.

## Intended Contract

- Tenant and venue ownership should be explicit at the schema level where
  possible.
- Required text/enum/status fields should have parser-safe constraints.
- Historical and payroll-adjacent records should preserve lineage.
- Schema changes must update `Application/Schema.sql`, add matching
  `Application/Migration/*.sql` files for existing deployed databases,
  regenerate types, preserve existing customer data, apply to the local dev DB,
  and pass startup verification when enums or constraints change.

## Exit Criteria

- Core constraints and nullable uniqueness fixes land with tests.
- Living schema guidance in `Application/AGENTS.md` and
  `Application/Migration/README.md` stays aligned with the final constraint and
  migration patterns.

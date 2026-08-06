# Database Migrations

`Application/Schema.sql` is the complete fresh-database schema. Files in this
directory are the ordered upgrade path for deployed databases containing
customer data; changing the schema without a deployment migration (or an
issue-recorded reason none is needed) is incomplete.

## Rules

- Preserve customer data by default. Dropping tables, columns, enum values, or
  rows requires an explicit issue, operator-approved runbook, verified
  backup/restore path, and rollback or recovery procedure.
- Prefer additive rollout: add compatible structures, backfill and verify, then
  tighten or retire compatibility in a separately controlled step.
- Account for IHP's transactional runner. Use parser-safe SQL and apply
  `IF EXISTS`/`IF NOT EXISTS` only where repeatability cannot hide drift.
- Record non-obvious backfill, constraint, trigger, index, and enum transitions
  beside the migration or in its operator runbook.
- `make db` resets local development data; it verifies fresh-schema parsing and
  startup only and is never a deployed upgrade strategy.

## Verification

After schema changes, regenerate types and typecheck. For parser-sensitive
changes, apply the fresh schema locally, restart/wait for IHP, and inspect the
resulting database shape. Migration-specific tests and operator checks remain
mandatory.

```bash
bash ./bin/in-env regen-types
bash ./bin/in-env typecheck
```

## Operator-Gated Changes

Runbooks in this directory own exact deployment procedures for forward-only or
destructive changes:

- `legacy-schema-retirement-151-runbook.md` — staged capture, approval, drop,
  and restore rehearsal for retired tables.
- `authoritative-time-boundaries-274-runbook.md` — wall-clock to instant cutover.
- `explicit-roster-shift-assignment-304-runbook.md` — explicit Staff/Open shift
  assignment migration.
- `roster-timesheet-suggestion-cutover-runbook.md` — retirement of legacy
  roster-to-Timesheet workers and activation of transient suggestions.
- `timesheet-pay-ledger-234-runbook.md` and
  `haskell-wage-cutover-239-runbook.md` — immutable ledger and wage-authority
  cutover sequence.

Do not infer production approval from a committed migration or runbook; use the
named approval boundary in that runbook.

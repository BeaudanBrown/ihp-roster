# Schema Hardening

Epic: [#53](https://github.com/BeaudanBrown/ihp-roster/issues/53).
Related unresolved work:
[#36](https://github.com/BeaudanBrown/ihp-roster/issues/36),
[#69](https://github.com/BeaudanBrown/ihp-roster/issues/69), and
[#72](https://github.com/BeaudanBrown/ihp-roster/issues/72).
GitHub owns status and dependencies.

## Intended Contract

- Venue/tenant ownership is enforced by schema constraints where practical,
  with application authorization remaining mandatory.
- Required text, enum, status, and nullable-uniqueness rules use IHP-parser-safe
  PostgreSQL shapes.
- Historical and payroll-adjacent records preserve lineage.
- Indexes/statistics support demonstrated query paths rather than speculative
  tuning.
- Every deployed schema change updates `Application/Schema.sql`, includes a
  customer-data-preserving `Application/Migration/*.sql` path, regenerates
  types, and passes migration/parser/startup verification.
- Destructive changes require a separate approved operator runbook, backup,
  restore rehearsal, and recovery boundary.

## Integration Points

- `Application/AGENTS.md` and `Application/Migration/README.md`.
- Domain/pay/Timesheet/leave specs affected by constraints.
- `Test/SchemaSpec.hs`, database-protection tests, and migration-specific checks.

## Exit Criteria

- Core constraint, tenant-integrity, nullable-uniqueness, index, and statistics
  issues are resolved with migrations and tests.
- Living schema and migration guidance reflects the final safe patterns.

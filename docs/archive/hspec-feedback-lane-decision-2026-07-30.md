# Hspec Feedback Lane Decision — 2026-07-30

This is point-in-time evidence for GitHub issue #207. Living commands and rules
remain in `README.md`, `Test/AGENTS.md`, and ADR 0004.

## Decision

Keep one user-facing mandatory Hspec command:

```bash
bash ./bin/in-env hspec-test
```

`hspec-test` remains complete by default and remains the Hspec command used by
required CI. Do not add routine-only or acceptance-only wrapper commands.
`TEST_FEEDBACK_LANE=routine|acceptance` remains an expert diagnostic interface
for suite-metadata analysis. Its output names omitted mandatory invariants, and
neither selection is acceptable merge evidence.

Keep `hspec-pure` as the useful fast additive command for pure helper and
contract work. Keep `hspec-db` as a diagnostic isolation dimension. Neither is
a replacement for complete Hspec.

## Current Inventory

Inventory at `55fc1c3b` reported:

- 93 registered suites and 1,322 examples;
- 41 pure suites / 539 examples;
- 52 database suites / 783 examples;
- 45 routine-correctness suites;
- 48 broad-acceptance suites;
- all 13 `InvariantFamily` values represented;
- 707 static `withCleanDb` call sites.

The registry now rejects removal of the final suite in an invariant family.
This makes the broader billing, communications, data-integrity/audit,
frontend-contract/live-update, observability, pay/export, support, rostering,
staff/compliance, test-infrastructure, timesheet/leave, access/onboarding, and
Xero responsibilities enforceable rather than relying only on the original
A/R/T/P/B acceptance identifiers.

## Measurements

These were single current-host observations, not benchmark medians. A
pre-existing focused `build/Test/Main` process prevented the exclusive baseline
lock, so selected-lane runs are deliberately labelled non-exclusive. The
relative conclusion is large enough that no speedup claim depends on small
variance.

| Selection | Examples | Command wall | Slowest Hspec shard | Mandatory evidence omitted |
| --- | ---: | ---: | ---: | --- |
| `hspec-pure` | 539 | 2.89s | 0.55s serial | A1–A7, R1–R5, T1–T7, P1–P7, B4–B7 |
| routine feedback, 6 shards | 397 | 5.55s | 1.10s | every A/R/T/P/B invariant |
| acceptance feedback, 6 shards | 925 | 22.38s | 19.66s | A4, R4, R5, T4, P2, P3, P5, B1, B2, B4, B7 |
| `hspec-db`, 6 shards | 783 | 23.59s | 21.01s | A4, A5, A6, R4, R5, T1, T3, T4, P2, B1–B4, B7 |
| complete `hspec-test`, 6 shards | 1,322 | 22.85s | 20.35s | none |

Routine feedback is materially faster but excludes every mandatory acceptance
category. Acceptance-only and DB-only cost approximately as much as complete
Hspec while still omitting required evidence. Stable user-facing commands for
those slices would therefore create ambiguity without useful routine savings.

The broader family metadata maps the named non-A/R/T/P/B evidence as follows:

- billing: `Billing`;
- MA000009 wage authority and source freshness: `StaffAndCompliance` plus the
  wage suites in `PayAndExports`;
- venue-time, immutable pay history, and exports: `PayAndExports`;
- schema/migration and immutable-ledger protection: `DataIntegrityAndAudit`
  plus the migration suites in `PayAndExports`;
- Xero export/submission behavior: `XeroPayroll`;
- generated contracts and live-update behavior:
  `FrontendContractsAndLiveUpdate`.

The metadata report prints every represented family and registry validation
fails if the final suite in any family disappears.

## Broader Verification Observation

`verify-fast` reached pure Hspec (539 examples, 0 failures in 0.54s) and then
failed after 17.09 seconds because Playwright requires the development
PostgreSQL/server environment. `verify-full` reached complete Hspec and then
found a stale unreachable `dialogBlockingAttrs` declaration during Weeder after
150.97 seconds. That declaration was removed during #207 and standalone Weeder
then passed. These observations reinforce that broader verification is a
composition of distinct authorities and environment preconditions, not another
Hspec feedback lane. Managed E2E/development state is owned by issue #213.

## Evidence Ownership

- Complete Hspec: deterministic domain, controller, persistence, fixture,
  golden, schema/parser, and generated-contract runtime evidence.
- Typecheck and compile-fail checks: impossible Haskell states and typed Surface
  ownership.
- Generator, frontend, architecture, and drift checks: checked-in generated
  artifacts, TypeScript/browser-unit behavior, import topology, and stale
  source ownership.
- Migration/deployment checks: upgrade ordering and customer-data-preserving
  deployment contracts; current-schema Hspec does not replace them.
- Playwright: real browser workflows and reachability; it remains a separate
  local/release tier rather than required Hspec CI.
- Stripe B8 sandbox/test-clock evidence: operator-only, documented in
  `Application/Billing/RUNBOOK.md`, and never represented as automated Hspec
  coverage.

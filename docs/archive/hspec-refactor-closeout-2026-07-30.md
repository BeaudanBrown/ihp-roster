# Hspec Refactor Closeout — Epic #197

Status: final reconciliation evidence, measured 2026-07-30

Related issues: #197, #198, #200, #201, and #203–#209

Living contracts: `Test/AGENTS.md`, `specs/00-readme.md`, `README.md`, and
ADR 0004

## Outcome

The refactor kept complete Hspec as one auditable protected gate while moving
persistence-independent behavior to pure seams, consolidating repeated domain
and controller matrices, retaining high-value security/compliance evidence, and
calibrating six shards from exclusive measurements.

| Metric | Initial #197 baseline | Final | Outcome |
| --- | ---: | ---: | --- |
| Suites | 88 | 93 | Five modules split into separately registered pure/DB responsibilities. |
| Examples | 1,353 | 1,322 | 31 redundant examples removed. |
| Pure suites/examples | 36 / 518 | 41 / 539 | 21 examples moved into fast pure feedback. |
| DB suites/examples | 52 / 835 | 52 / 783 | 52 DB examples removed or moved without dropping authority. |
| Broad resets | 728 | 715 | 13 unnecessary resets removed; isolation-sensitive cleanup retained. |
| Pure Hspec | 0.5288s single | 0.548s median | Sub-second target met. |
| Complete six-shard wall | 22.00s single | 23.010s median | Under 60-second target; no unsupported speedup claim. |
| Slowest/median shard | 1.23 | 1.149 median | Balance improved; under 1.5 threshold. |
| Mandatory evidence | represented | all represented | All 13 invariant families and automated A1–A7/R1–R5/T1–T7/P1–P7/B1–B7 retained. |

The final seeded serial run passed all 1,322 examples in 76.508 seconds. Three
exclusive warm complete measurements passed with zero failures. The default
unforced command selected six equal declared-weight shards and left no shard
databases or test backends.

## Architecture Reconciliation

- `hspec-test` is complete by default and is the sole protected Hspec gate.
- CI remains the exact sequential pair `typecheck` then complete `hspec-test`.
- `hspec-pure`, `hspec-db`, focused filters, and low-level routine/acceptance
  selections are diagnostic. They report conservatively omitted mandatory
  evidence and cannot be called complete.
- `verify-fast` is additive feedback. `verify-full` composes complete local and
  release authorities; it does not redefine CI.
- `Test/Suite.hs` plus `Test/Suite/Metadata.hs` is the authoritative suite
  inventory. Registry validation enforces valid isolation/reset/visibility
  combinations, acceptance ownership, invariant-family representation,
  controlled mocks, and positive finite weights.
- Broad cleanup remains the isolation-safe default for nested transactions,
  jobs/queues, sessions, constraints, audit/version rows, immutable approval
  facts, and committed cross-context visibility. There is no reset quota.
- Verification-owned migration checks select the managed Hspec PostgreSQL socket
  explicitly rather than inheriting development `PGHOST`. NixOS module checks
  evaluate a filtered working-tree source, so ignored development sockets and
  runtime artifacts cannot invalidate an otherwise clean verification run.

## Preserved Evidence Boundaries

Pure WageEngine, VenueTime, assignment, and source-policy suites own exhaustive
domain decisions. Database adapters own persisted projection and strict
batching. The approved pay ledger owns immutable historical reconstruction.
Billing persistence/webhook/reconciliation suites retain idempotency,
signature, ordering, and sensitive-data evidence. Exact export goldens remain
the byte-level payroll authority. Xero readiness/preview/submission suites own
sealed-fact publication and controlled requests. Dedicated auth, malformed-ID,
destructive mutation, and cross-venue tests remain registered.

Stable `HIGA-*` scenario IDs map MA000009 examples to deterministic wage, export,
and Xero evidence. Current-schema tests do not replace real migration,
predecessor-upgrade, cutover, or deployment-order checks. Hspec does not replace
type/compile-failure, generated/frontend/architecture drift, Playwright, or
operator-only Stripe sandbox/test-clock evidence. Billing `B8` therefore stays
in `Application/Billing/RUNBOOK.md` rather than suite metadata.

## Targets And Non-Claims

All explicit acceptance thresholds were met: complete Hspec stayed below 60
seconds, pure Hspec stayed below one second, shard-tail ratio stayed below 1.5,
and complete serial/sharded runs passed without leaks.

The final complete median is 1.01 seconds slower than the initial single
observation. This is within repeated reset variance; the project makes no wall
speedup claim. Reset count fell only 1.8% because correctness required retaining
most broad cleanup. Neither wall time nor reset count is a future quota.
Acceptance-only and DB-only selections remained near complete-suite cost and
were deliberately not promoted to stable gates.

## Evidence

The retained measured decision and final benchmark are
`hspec-feedback-lane-decision-2026-07-30.md` and
`hspec-final-performance-evidence-2026-07-30.md`. Intermediate plans,
inventories, and generated snapshots remain available in Git history.

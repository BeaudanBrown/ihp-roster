# ADR 0004: Complete Hspec Is The Protected Test Gate

Status: accepted

Date: 2026-07-30

## Context

The Hspec registry supports useful pure/database and routine/acceptance
selections. Several partial selections were plausible protected gates, but
measurement showed that database-only and acceptance-only cost approximately as
much as complete Hspec while omitting mandatory evidence. Routine-only is fast
but omits every mandatory A/R/T/P/B category. A reset quota would also reward
weaker isolation rather than better seams.

## Decision

`hspec-test` with its default complete registry is the sole protected Hspec
gate. Required CI runs `typecheck` followed by complete `hspec-test`.

`hspec-pure`, `hspec-db`, focused matches, and
`TEST_FEEDBACK_LANE=routine|acceptance` remain additive diagnostics. They must
report omitted invariants and cannot be presented as complete evidence.

The registry records pure/database isolation, reset need, committed visibility,
feedback responsibility, invariant family, exact acceptance ownership, fixture
cost, controlled external mocks, and approximate runtime. Validation rejects an
unowned mandatory invariant or removal of the final suite representing an
invariant family. Broad cleanup remains the default where isolation semantics
require it; there is no reset-count quota.

Verification authorities remain separate. Hspec does not replace type/compile
failure, generated-contract/frontend/architecture drift, migration/deployment,
real-browser, or operator-only provider evidence.

## Consequences

New suites must select a strong domain seam before adding controller matrices,
register complete metadata, and preserve dedicated security and cross-tenant
coverage. Pure feedback remains sub-second in Hspec execution, while the
complete six-shard suite remains the merge authority.

Partial selections are useful for iteration but cannot make CI faster by
silently dropping compliance, billing, audit, migration, or composed evidence.
Runtime weights are measured and coarsely rounded; they are balancing hints, not
example-count proxies or permanent performance assertions.

## Alternatives Considered

- Protect routine-only Hspec: rejected because it omits all mandatory acceptance categories.
- Protect acceptance-only or database-only Hspec: rejected because each costs near the complete suite while still omitting evidence.
- Enforce a fixed reset quota: rejected because broad cleanup is required by nested transactions, queues, constraints, sessions, committed visibility, immutable ledgers, and other isolation-sensitive behavior.
- Split mandatory evidence across several user-facing Hspec commands: rejected because one complete command is easier to audit and harder to weaken accidentally.

## Links

- Tickets: #197, #203, #207, #208, #209
- Workstreams: `docs/workstreams/maintenance.md`
- Living docs: `Test/AGENTS.md`, `specs/09-testing-and-acceptance.md`, `README.md`
- Evidence: `docs/archive/hspec-feedback-lane-decision-2026-07-30.md`, `docs/archive/hspec-final-performance-evidence-2026-07-30.md`

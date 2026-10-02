# Daysheets

[Product contract](../../specs/07-daysheets.md) · [Engineering contract](SPEC.md)

`Contract` and `Validation` own definition meaning. `Formula` bounds the linked
DSL graph before it becomes an expression tree. `Schema` and `Wire` reuse the
backend FrontendContract DSL and exact carrier parsing; no separate JavaScript
formula language belongs here. `Number` and `Results` supply exact arithmetic
and unavailable-result laws. `Evaluation` accepts a validated immutable saved
snapshot, rejects calculated overrides and foreign references, and evaluates
fields/advisories with a shared per-field-batch work budget.

`Storage` owns membership-scoped staging, publication, reference updates and
immutable capture. `DefinitionCodec` and `ReferenceCodec` own server documents;
`References` validates active links and explicit retirement plans. The approved
staging/publication boundary is retained in `SPEC.md`.

`Entry` owns bounded nominal numeric/clock form spelling and exact semantic
parsing against the pinned field type. Percent entry is human percentage units;
stored percentages remain ratios. It accepts no formulas or floating-point
coercion and retains submitted spelling for errors/conflicts.

`Daily` owns the server-only saved-content document and pure edit decisions:
per-cell revisions, fixed captured checklist identities, open-row tombstones,
and exact deletion dependency confirmations. Persistence must authorize and
serialize each mutation against the latest document; browser boundaries must
expose typed commands rather than this opaque storage document. `DailyStorage`
provides scoped reads, atomic explicit creation, latest-state mutations, and
idempotent submission. `Storage.withDefinitionCapture` keeps initial daily
materialization and its immutable meaning in the same authority transaction.

`Authority` rechecks live venue/membership authority under ordered locks.
`Recipients` owns admin/owner-only external address management independently of
versioned layouts. Address identities are immutable, removal is permanent, and
re-addition creates a new identity. The shared mail worker owns transport;
`EmailContract` names the frozen-report reference boundary. Controlled-provider
and committed concurrency tests live in `Test/DaysheetRecipientsSpec.hs`.

The pure evaluator does not authorize venue access, persist daily entries,
resolve operational-day instants, or send reports. Callers must preserve the
product's pinned-definition/current-venue boundaries. Tests live in
`Test/DaysheetContractSpec.hs`, `Test/DaysheetNumberSpec.hs`, and
`Test/DaysheetEvaluationSpec.hs`; reference and persistence suites cover staging
and historical isolation.

Focused checks:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match Daysheet
```

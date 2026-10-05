# Daysheets

[Product contract](../../specs/07-daysheets.md) · [Engineering contract](SPEC.md)

`Contract` and `Validation` own definition meaning. `Formula` bounds the linked
DSL graph before it becomes an expression tree. `Schema` and `Wire` reuse the
backend FrontendContract DSL and exact carrier parsing; no separate JavaScript
formula language belongs here. `Number` and `Results` supply exact arithmetic
and unavailable-result laws. `Evaluation` accepts a validated immutable saved
snapshot, rejects calculated overrides and foreign references, and evaluates
fields/advisories with a shared per-field-batch work budget.

`Designer` owns server-side structural edits and nested calculation replacement.
It preserves identities and uses whole-definition validation both to filter
proposed formula choices and to reject forged or dependency-breaking edits.
Its edit algebra is not a browser payload; browser controls require generated
commands. `Storage.readDesignerState` reads the draft or published definition
without creating records; `Storage.editDraft` applies edits under fresh venue
admin/owner authority and exact draft/base-revision checks. Ordinary edits never
silently rebase a stale draft after live reference changes.
`Storage.editDraftReferences` exposes typed row/value/retirement edits under the
same revision guard. New values use canonical reference validation; old staged
values can be repaired one at a time, including explicitly clearing removed
fields. Retirement requires explicit dependency choices and takes effect only
on publication; no historical capture is rewritten.

`Web.Controller.DaysheetDesigner` and `Web.View.Daysheets.Designer` own the
admin/owner field/list forms and explicit publication page. Generated
`Surface.DaysheetDesigner` requests carry finite Haskell-owned control kinds and
exact revisions, never replacement definition JSON. Each editor mounts one
editable form, preserves submitted values on rejection, and offers explicit
discard. Saved changes and durable configuration invalidation commit together;
clean observers refetch while dirty editors retain their input. Navigation from
daily entry uses its existing pending-edit gate. Venue reference lists expose
single-cell editors using saved field types, explicit blank clearing and
retirement controls. Dependent links must be reassigned or explicitly cleared
before retirement; active reference lists cannot be removed or repurposed first.
Obsolete staged values have explicit clear controls. Reference edits and
retirement remain draft-only until publication.

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

`EntryLayout` binds authored occurrences to authorized root/row cells without
exposing a render document to JavaScript. `Mutations` composes daily persistence
with the shared durable live publisher. `Entry.deletionToken` fingerprints scope,
target and incoming revisions; it is concurrency evidence, never authority.

Ordinary single-page entry lives in `Web/Controller/Daysheets.hs`,
`Web/Daysheets/{ReadModel,LiveUpdates}.hs` and `Web/View/Daysheets/`.
`Surface/Daysheet` owns its generated typed commands and live fragments. The
shared dirty-form owner and settled-form gate retain pending, invalid and
conflicting edits; deleted-row values require explicit discard. No pagination
or feature-specific browser transport is involved. Browser fixtures are authored
in `Test/Support/Daysheet.hs` and seeded by `Test/E2EDaysheet.hs`, independent of
the ignored workbook.

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
bash ./bin/in-env e2e e2e/daysheet-entry.spec.ts --reporter=line
```

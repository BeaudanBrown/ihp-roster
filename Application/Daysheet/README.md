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

`Web.Daysheets.LayoutEditing` adapts generated section/report/block controls to
validated definition edits; `Web.View.Daysheets.LayoutDesigner` renders their
single-form editors. Entry and report layouts select the same fields but retain
independent section/content order. Tables select columns, grouping and ordered
sort keys; explicit move controls reorder fields, lists, reports, sections,
content, columns and sort keys without replacing identities. Advisory controls
select boolean fields, and message-only edits preserve existing complex
conditions. Report targets are a closed supported selection, not recipient
addresses or a second calculation model. Read-only index mutations use semantic
actor refresh; editor saves navigate back to the index after acknowledging the
saved form. Passive observers refetch authorized fragments independently.
Choice options have individual add/rename/remove/move controls: renames and
moves preserve option IDs; removing the last option or a formula-referenced
option fails canonical validation. Earlier captures retain their original
choice labels and order.

`Designer.Calculation` prepares compatible, cycle-safe calculation choices from
server-owned primitives using the canonical validator. Focused lexical scopes
come from the saved expression location: aggregate `Item` never replaces the
enclosing `Current` row. Reference traversal is bounded and uses canonical type
inference; menu choices carry internal edits, not browser expression documents.
Their snapshot validity never replaces under-lock revision/authority checks.
`Web.Daysheets.CalculationEditing` owns bounded navigation tokens and typed
constant requests; `Web.View.Daysheets.CalculationDesigner` renders native
part-selection controls and a separate dirty-safe constant form. Selecting a
part stages it immediately; visible example constants remain editable before
explicit publication. Calculation pages refresh semantically at the same saved
location. No expression document or evaluator is sent to the browser.

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

`Saved` prepares one authoritative saved-state evaluation for entry and report
projection. It owns exact value display, preserved reference labels and stable
table ordering; operational times sort against the evaluator's 06:00 boundary.
This internal model contains source fields and must not itself be serialized as
a selected report. Nominal choice/reference sorting uses preserved display
labels with identity tie-breaks, keeping equally named groups contiguous.

`Report` is the selected-content boundary over that saved evaluation. It emits
only authored sections, fields, tables and checks, with resolved nominal labels
and exact typed values for subsequent renderers. Hidden dependency labels are
redacted from unavailable reasons; row checks use ordinal identities rather
than discovering hidden text fields. Report text remains plain data for escaped
HTML/non-executable spreadsheet handling. All selected advisory checks share one
evaluator work budget, including checks repeated across rows.
`Web.View.Daysheets.Report` renders escaped, read-only Draft/Live previews for
captured reports with the formatted output enabled. Pages and live fragments
use the same scoped read, never create/submit/capture reports, and refresh from
the shared Daysheet resource. Preview navigation uses the pending-edit gate and
supports native GET forms. Excel-only reports retain the same projection but
are not exposed as formatted browser outputs.

`ReportCodec` retains versioned selected results and their original display copy
without reevaluation or current reference lookups. It is a server-only storage
boundary, not a browser report document. Calculated money retains exact fractions;
authored/entered money still requires whole cents. Unknown versions, unresolved
choice identities, NUL and oversized documents fail closed. Frozen persistence,
capture authority and delivery must wrap this codec; it alone creates no report.

`Cutoff` owns venue-local deadline, early arming and strict post-lock timing
admission. `CutoffCapture` provides the real venue-lock/transaction boundary with
an injectable clock: preparation waits outside locks, capture waits at most one
second beforehand, late attempts skip, and callback failures roll back. It does
not yet register jobs, persist report snapshots or invoke mail transport. See the
scheduled-cutoff contract in `SPEC.md` and the committed concurrency tests.

`ReportStorage` atomically persists selected frozen content, source revision,
origin/time, deliberate Send identity and intended recipient IDs with shared v2
mail jobs. Repeated manual requests reuse the same immutable run; fresh nonces
capture current saved data. Scheduled capture uses `withScheduledDaily`, skips
missing/unsubmitted days and captures all configured formatted reports under one
cutoff transaction. The database seals snapshots against mutation/deletion and
checks submitted source/venue/revision and active scoped recipient identities.
This service is not yet connected to the scheduler or Send UI.

`ReportDelivery` is installed in the shared mail pipeline. It verifies frozen
venue/report identity, exact captured recipient membership and address, then
renders retained selected content without loading the live Daysheet/evaluator.
Missing references skip and corrupt documents fail closed. Shared recipient
locking, cancellation, provider correlation and retries remain transport-owned.
`Application.Helper.View.DaysheetReport` supplies common escaped HTML and explicit
plain-text statuses; `Web.Mail.DaysheetReport` adds frozen origin and actual
capture/cutoff identity, without attachments or authenticated URLs.

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

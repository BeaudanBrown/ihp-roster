# Daysheet Definition Contract

Product authority: [Configurable Daysheets](../../specs/07-daysheets.md).
Definition validity does not establish venue authorization or delivery authority.
A structurally valid definition is never authority to read a venue or day.

## DSL And Wire Boundary

The Haskell vocabulary in `Contract` owns operations and their types;
`Validation` owns compatibility and dependency checks. `Schema` declares the
exact flat formula envelope through the existing FrontendContract DSL. Its
closed scalars reflect the same operation types: browser code must not declare
another operator union or infer valid operations from their names.

The linked-node representation was explicitly approved for this epic. Unlike
nested wire expressions, a flat node list does not require recursive schema
references in the shared validator. Nodes cannot introduce functions, scripts,
SQL, another day, or external data. IDs are local to a formula; field/list IDs
are stable definition identities, not record or venue authority.

`Wire.decodeFormula` enforces a byte limit, exact DSL decoding, graph validity,
expansion limits, and type inference. Numeric components travel as bounded
canonical decimal strings, never JavaScript floating-point numbers. The
server-only schema root becomes a browser-reachable registered declaration
when the designer consumes it; the existing checked IR and TypeScript renderer
must generate that boundary. Do not handwrite TypeScript contracts or use an
opaque JSON field to bypass this root. Full-definition persistence must embed
these formulas through the same declarations rather than a second codec.

Node sharing does not waive the expanded expression budget. Each occurrence
consumes budget, so a small doubling DAG cannot construct an exponential tree.
Unreachable nodes are rejected, not ignored. Changing the encoding or semantics
requires a new contract version; published definition versions are separate
from this engine contract version. Existing pinned definitions must remain
readable and must not silently reinterpret old rules.

## Numeric Meaning

`Number` uses reduced exact rationals, with bounded numerator and denominator.
It exposes no unchecked constructor. Arithmetic revalidates every result; an
out-of-range runtime result is unavailable, not wrapped, truncated, or saturated.
The current limits and operation/type matrix are executable authorities, not
browser defaults. Boundary parsers enforce size before reading integer text.

Whole numbers, decimals, AUD money, and percentages remain distinct types.
Money entry/constants require whole cents. Intermediate money retains exact
precision. Explicit cent rounding uses ties away from zero. Percentages are
ratios: 1.6% is 0.016. `PercentageRatio` is the explicit dimensionless conversion
used in the denominator of surcharge removal. Multiplication by a whole or
decimal scalar preserves money. Dividing money by money produces a decimal;
dividing money by a scalar preserves money. No implicit text or money casts.

## Scope And Aggregation

Root refers to single Daysheet fields, Current to the enclosing row, and Item
to the selected aggregate row. A reference path follows single-record links
through the pinned definition only. Runtime lookup must be restricted to the
current Daysheet's daily records and its preserved venue records. Valid UUIDs
alone cannot establish that scope. Venue reference calculations cannot read
root/daily data.

Engine contract version 2 adds `ChecklistReference Current/Item`, a typed leaf
for the paired preserved record of a reference-checklist row. It is invalid in
root/open-list/venue-reference contexts and unavailable if the preserved entry
is missing. Daily persistence must use the preserved row key in each checklist
list, enforce exactly the captured source key set, and prohibit editing that
pairing. Authors can expose it as a normal calculated reference field and follow
its fields through ordinary paths. No implicit editable field is injected.
Version 1 remains readable with its unchanged vocabulary and meaning; existing
captures are never migrated to version 2.

A filtered/grouped sum is a Sum fold with a typed Boolean predicate. Grouping
compares Item references with Current references. Nested folds are not allowed;
intermediate calculated fields provide reusable stages without nested iteration.
Count returns the number of selected records and does not require their value
operand to be available. A conventional constant operand may be supplied.
An average is Sum divided by Count, not a user-defined function.

An empty Sum is a known zero in its declared numeric type. Empty Count is known
zero. Division by zero (including an empty average) is unavailable. An unavailable
filter predicate makes the aggregate unavailable: silently excluding an unknown
row could invent a financially misleading total. A false predicate excludes
that row before inspecting its value. Included unavailable values propagate.

## Unavailability And Conditions

Unknown daily data does not invalidate a definition. Missing inputs/references,
zero denominators, numeric overflow, and exhausted evaluation budget produce
unavailable results with plain-language reasons. Zero, false, and blank text
are not interchangeable with missing input.

Both branches of a conditional are validated at publication. At runtime only
the selected branch is evaluated; an unavailable condition preserves its reason
and selects neither branch. Boolean And/Or propagate unavailable operands rather
than concealing incomplete inputs through Boolean shortcuts. Advisory checks
map known true/false to Passed/Concern; unavailable maps to Not evaluated with
the originating reason. None of these outcomes overrides permission checks or
adds a submission/send gate.

## Publication And Historical Meaning

Validate the complete proposed definition, including layouts and checks, on
any definition edit. A removed field cannot remain referenced by a formula,
table, grouping/sort control, or displayed summary. The server remains the
publication boundary even when designer controls offer only valid choices.
`validateDefinition` supplies semantic checks, not a replacement for bounded
request decoding or authorization.

Reference retirement and daily row deletion are data mutations, not definition
edits. Their preservation and confirmation rules remain in the product spec.
Reference definitions may contain calculated fields using reference-only data;
capture must preserve the published definition and source reference data needed
to retain their meaning. Frozen reports capture results, not a promise to
recompute them under future evaluator changes.

## Daily Content Mutation Core

`Daily` is a pure server-owned document boundary, not an authorization or browser
request API. Documents are capped at 4 MiB and validated against the immutable
captured definition/reference data. Blank cells keep revision metadata; a
clear-and-reenter cycle cannot make an old edit current again. Independent
fields compare independent revisions, not the whole document's revision.

Checklist row keys exactly match the captured source list. Open-row deletion
compares the target revision and exact incoming cell/revision set with explicit
approval. Changed dependencies or target values require fresh confirmation.
Clearing links advances their revisions, retains other rows/values, and deletes
the target atomically at the persistence boundary. Only deleted identities are
retained to reject stale add/edit retries; deleted content is not an edit-history
archive. Re-adding a row is a new deliberate identity.

`DailyStorage` rechecks current venue/membership authority for every read/write.
Creation, definition capture and initial checklist materialization commit or
roll back together under the ordered venue lock; reads never create records.
All edits load the latest saved document under that same serialization boundary.
The database seals venue/day/capture identity, advances revisions, and prohibits
reopening submission, but does not freeze submitted content. Last-edited metadata
changes with content, not repeated Submit requests. Submission creates no report
or mail job and applies no completeness/advisory gate. Browser orchestration must
settle local pending saves/conflicts before invoking Submit or future Send.

The canonical daily document cap is 4 MiB; the SQL JSONB text cap is 8 MiB to
allow PostgreSQL's representation whitespace. NUL text is rejected before SQL.
No per-field before/after values are written to the audit stream.

## Scheduled Cutoff Boundary

The operator-approved mechanism pre-arms one venue/day capture task before the
cutoff, waits outside the database transaction, then acquires the existing venue
serialization lock at most one second before the following venue-local 06:00.
One task must capture all eligible configured reports for that day; independent
per-report workers would contend across the same deadline. The queue's default
future-job polling interval is 60 seconds, so the plan arms two minutes early.
No active scheduler registration is implied by this boundary alone.

`Cutoff` resolves the civil boundary through the shared timezone authority,
including DST, with no UTC fallback. `CutoffCapture` rechecks live venue state and
configured timezone under the same lock used by daily saves and recipient
changes. It rechecks time after lock acquisition: a delayed worker or contended
lock arriving at/after cutoff skips without invoking capture. Clock rollback
never extends the deliberate lock wait. Callback writes share one transaction;
exceptions or typed errors roll back the whole capture. An outer transaction is
rejected so preparation cannot accidentally retain database locks.

The lock remains held through the callback and commit. Edits saved before
acquisition are included; waiting edits resume afterward and affect only live
data. The snapshot must store actual capture time separately from its scheduled
cutoff, never backdate a late observation. Admission is transaction-local and
cannot be persisted/reused by retries after failure. Delivery runs only after
commit through the shared mail pipeline. Submission eligibility, immutable
snapshot storage and recipient/job creation belong to the capture callback, not
the clock policy; blank figures and advisory concerns are not eligibility gates.

## Frozen Persistence

`ReportStorage` captures formatted configured reports only, never caller-supplied
content or destinations. Manual capture rechecks membership under the venue lock,
requires submission and binds its request nonce to venue, sender, Daysheet and
report. Concurrent/retried attempts return the existing run without recalculating
values, adding recipients or enqueueing again. A new nonce deliberately creates
a fresh run; older content and intended-recipient sets remain unchanged.

Snapshot insertion and every shared external-recipient mail job use the same
transaction. Any failure rolls back the entire run/batch. Scheduled capture uses
no fabricated account and also refuses source timestamps after cutoff, including
clock-anomaly cases. The immutable scheduled row is its background provenance;
manual capture additionally emits the typed report-captured audit event.
Transport is not invoked by capture. The installed frozen-mail resolver reads
only retained selected content and immutable capture metadata; it verifies the
exact captured recipient set as well as current recipient eligibility through the
shared pipeline. Later edits, recipient additions and retries cannot select new
values/destinations. History and scheduler wiring remain integration work.

`daysheet_report_snapshots` stores the captured definition link, saved revision,
selected versioned content and distinct intended recipient identities. Recipient
rows already preserve immutable addresses, so later cancellation cannot rewrite
the original destination and re-addition cannot join an old run. PostgreSQL
rejects mismatched source scope, unsubmitted sources, stale revisions, invalid
origin/sender/cutoff combinations, foreign/removed/duplicate recipients and all
snapshot UPDATE/DELETE operations. The application validates selected content;
SQL does not duplicate the report codec/evaluator. Selected JSON is capped at
16 MiB canonically (32 MiB PostgreSQL representation), with at most 10,000 intended
recipients per report; exceeding safety ceilings rejects rather than truncates.

Migration `1791259200-daysheet-frozen-reports.sql` is additive and rewrites no
existing records. Rollback to an older application can leave the new objects
unused; retain all snapshots/jobs rather than dropping them. Controlled retention
remains the only deletion path. No deployment or live-mail approval is implied.

## Daily Entry Boundary

Daily entry stays on one page with related figures together. Engine ceilings
are safety limits, not a pagination requirement. The eight-terminal fixture is
an authored largest-venue example; verification never requires the ignored
operator workbook. Authored grouping/sorting changes presentation only.

An entry occurrence identifies a placement in the pinned layout, not a second
field. Repeated placements share the saved cell/revision but have distinct DOM
identities. Calculated and captured venue fields remain read-only. The Surface
DSL owns command fields, live resources, gate roles and generated adapters;
the saved document never crosses the browser mutation boundary.

IHP AutoRoute does not safely decode optional UUID arguments. Optional row route
tokens therefore enter the controller as `Maybe Text`, undergo strict UUID
parsing, and are then checked against the occurrence's pinned list and saved
snapshot. The generated cell contract remains an optional UUID. Route tests
exercise IHP's actual parser, not only direct controller calls.

Change/blur autosaves and explicit Save share ordinary forms. The shared dirty
owner observes input/change before HTMX dispatch, accepts only explicit saved
acknowledgements, and preserves newer edits and failed responses. Submit and
other final controls use the shared typed settled-form gate, not a second dirty
state owner. Native forms retain explicit Save and error recovery. Known errors
also disable server-rendered final controls until resolution.

Same-cell conflicts retain submitted and saved values for explicit replacement
or keeping the saved value. If another manager deletes a row, a rejected edit
retains its submitted value for copying and explicit discard; it cannot recreate
the row. Recovery remains protected even if the deleted row was the last
editable content. Discard requests a typed body resync without a mutation or
publication event. Replacement body roots carry their complete current child
fragment inventory.

Daily writes, audit and durable live invalidation share one transaction. Typed
operations nested beneath that publisher use the shared rollback helper's
savepoint on the existing connection; a typed failure rolls back local writes
and an outer publication failure rolls back the successful inner operation.
Advisory passes are quiet, concerns prominent, and unavailable checks explain
why. None adds a submission gate.

## Staged Reference Corrections And Storage

A draft contains both the proposed definition and its proposed reference data.
An incompatible reference-field type/choice/target change may be saved as a
draft, but cannot publish until the admin explicitly corrects the affected
reference values. Publication switches both documents in one transaction;
current published data remains usable until that commit. This workflow was
explicitly approved; it never edits historical instances, including Draft
Daysheets.

The server persistence document is owned by `DefinitionCodec`; expressions
inside it use the same flat FrontendContract DSL encoding as `Wire`. The
surrounding versioned domain document is server-only, not an opaque browser
request payload. Designer actions must operate through their generated typed
request boundaries. Both stored decoding and publication revalidate meaning.

`Storage` owns ordinary membership-scoped mutation authority. It re-reads the
current membership under lock, denies global-role substitution, and serializes
by venue before locking membership. Configuration revision detects changes to
the live reference set; a separate draft revision detects concurrent editing.
Publishing a draft based on stale live references fails rather than overwriting
newer data. Callers retain unsaved inputs and require an explicit reviewed save
against the new base. Typed error results roll back the transaction.

Ordinary reference additions/edits may update live data without republishing
the definition. They cannot remove identities or change retirement state.
Retirement requires an observed revision and explicit dependent reassignments
or retirements; unresolved active links reject the entire operation. Retired
identities are preserved in configuration documents and never restored
implicitly. Only active entries enter new captures. Captures have one unique
venue/Operational-day identity and retain immutable version/reference meaning.

Database guards reject changes/deletion of published versions and captures.
Venue equality is enforced alongside single-column foreign keys because the
pinned IHP schema parser does not support composite foreign keys. Deployment
verification uses the additive migration's real-runner rehearsal and preservation
fixtures; no development reset is a customer-data upgrade strategy.

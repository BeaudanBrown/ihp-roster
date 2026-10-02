# Daysheet Definition Contract

Product authority: [Configurable Daysheets](../../specs/07-daysheets.md).
This subsystem owns definition meaning, not venue authorization or delivery.
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

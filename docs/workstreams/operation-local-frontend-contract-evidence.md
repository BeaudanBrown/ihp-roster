# Operation-Local Frontend Contract Evidence

GitHub issues: `#345`, `#346`, `#347`

Affected living contracts:
`Application/Helper/FrontendContract/README.md`,
`Application/Helper/FrontendContract/Surface/README.md`

## Unresolved Intent

Request adapters should present a deep module: one small nominal operation
interface should hide declaration search, field evaluation, metadata reflection,
parser construction, and whole-Surface completeness. ADR 0006 chooses generated
operation tokens and operation-indexed evidence. The Roster Action pilot and
subsequent rollout remain unresolved implementation work.

The current interface exposes a complete promoted Surface even though a caller
needs one operation:

```haskell
SurfaceActionFields
    (AdapterFamilySurface RosterAdapterFamily)
    NavigateRosterWeek
```

`SurfaceActionFieldSpecs` then searches `SurfacePrimitives spec` through
`FindSurfaceAction`. The replacement must remove that search from generated
caller interfaces without creating another declaration authority.

## Chosen Interface

The generated request seam uses a unique token for each declaration and kind:

```haskell
data NavigateRosterWeekActionOperation

type instance ActionSurface NavigateRosterWeekActionOperation = Roster
type instance ActionMarker NavigateRosterWeekActionOperation = NavigateRosterWeek
type instance ActionFieldSpecs NavigateRosterWeekActionOperation =
    '[ Field WeekOffset 'WireInt
     , Field RosterGroupId 'WireUUID
     ]

navigateRosterWeekActionFields ::
    Int -> UUID -> ActionFields NavigateRosterWeekActionOperation
navigateRosterWeekAction ::
    ActionFields NavigateRosterWeekActionOperation -> FrontendSurfaceAction
parseNavigateRosterWeekActionParams ::
    (?request :: Request) =>
    Either [SurfaceRequestFieldError]
        (ActionFields NavigateRosterWeekActionOperation)
```

The token—not the DSL declaration marker alone—is nominal identity. Action and
Intent use distinct token kinds, so a same-marker cross-kind declaration remains
valid without making bundles interchangeable. `ActionSurface` returns only the
compact Surface name marker. `ActionFieldSpecs` contains one declaration's
ordered fields and is the sole field-list input to construction, lookup,
serialization, and parsing.

Production facades continue to expose named operation functions. They do not
expose token constructors, evidence constructors, raw `SurfaceFields`, a
re-indexing function, or a function accepting names/fields as strings. Existing
read-only `SurfaceFieldBundle` operations may be implemented for
`ActionFields operation`, but its field specs must resolve through
`ActionFieldSpecs operation`, never a full Surface lookup.

Generated term evidence carries checked request metadata:

```haskell
navigateRosterWeekActionEvidence ::
    ActionEvidence NavigateRosterWeekActionOperation
```

Its constructor is private. The generator renders it from the checked
`HtmxActionIR` used by ordinary contract generation. Runtime code consumes this
evidence instead of invoking `ReflectPrimitive (FindSurfaceAction ...)`.
Generated TypeScript continues to come directly from the same checked IR.

## Private Whole-Surface Proof

Each request kind has one private proof module emitted into the temporary
generated-code verification tree. Conceptually:

```haskell
type RosterActionAuthority =
    AssertCanonicalActionOperations RosterSurface RosterActionOperations
```

The proof checks set equality between canonical declarations and generated
tokens, exact compact ownership, canonical markers, and equality of ordered
field presence/wire specs. Missing, duplicate, extra, or mismatched operations
fail blocking generated-code typecheck. The proof may reduce the complete
Surface because it is not installed into `app-lib`, published, imported by a
facade, or rooted as runtime code. Its renderer remains retained generator
source, so the guarantee is compile/blocking-verification authority rather than
runtime validation.

Generator inventory validation continues to own builder, metadata, and parser
eligibility. All request output and proof candidates are produced and checked in
one mandatory generation result. TypeScript parity remains owned by canonical
checked IR rendering and generated drift, not by copied proof metadata.

## Alternatives Compared

| Design | Caller interface | Global authority | Diagnostics | Expected depth | Decision |
| --- | --- | --- | --- | --- | --- |
| Whole-Surface-indexed bundles | Complete Surface plus marker | Direct family search | Focused field errors, but owner search can expose the Surface | Shallow: every caller carries global machinery | Reject |
| Operation-indexed families over nominal tokens | One token and one local field list | Private set/field equality proof | Existing declaration-directed diagnostics reduce local specs | Deep: compact caller, private global implementation | Choose |
| Concrete generated record per operation | Opaque concrete type and generated accessors | Same private proof | Native record errors plus generated wire diagnostics | Potentially deeper, with more declarations/instances | Measured fallback |
| Checked-IR/runtime validation only | Minimal type interface | Runtime/IR checks | Caller misuse no longer fails compilation | Superficially small but weak | Reject |

Concrete records remain an allowed fallback only if the pilot proves GHC still
serializes excessive family evidence. They must be generated from the same IR,
use shared wire evaluation, satisfy the private proof, and provide no handwritten
or raw escape hatch.

## Guarantee Matrix

The durable matrix is
`Config/nix/frontend-operation-evidence-matrix.tsv`. It maps every fixture
registered by `frontend-surface-compile-fail-check` to its guarantee, unchanged
existing-fixture treatment during the Roster pilot, full-rollout seam, and any
new Roster Action pilot fixture that must exercise the equivalent guarantee.
The compile-failure command rejects missing, duplicate, stale, or malformed
rows and requires the nine named pilot fixtures to be unique, so prose does not
mirror a fixture inventory.

The matrix deliberately distinguishes the pilot from rollout. Every existing
fixture remains unchanged during #346 because current Action fixtures are
non-Roster or generic and all Intent, Profile Toggle, and AppShell fixtures are
outside the pilot. Its final column names Roster Action equivalents for missing,
extra, order, presence, wire, owner, field, raw-rebinding, and cross-operation
guarantees; #346 registers those fixtures with their intended focused
diagnostics. #347 then moves remaining Action/Intent rows to the selected
operation-local seam.

| Guarantee class | Operation-local owner | Blocking evidence |
| --- | --- | --- |
| Nominal operation and compact Surface owner | Kind-specific token, `ActionSurface`/`IntentSurface`, nominal bundle role | Wrong-owner and cross-operation compile failures; private set proof |
| Exact field marker, order, presence, and recursive wire | `ActionFieldSpecs operation` / `IntentFieldSpecs operation` | Missing, extra, order, presence, wire, and wrong-field diagnostics |
| Closed scalar/state source type | Existing `KnownSurfaceWireValue` and `WireClosed` over local specs | Wrong closed-domain compile failure and generated parser tests |
| Matching builder, metadata, and parser | One generated token/evidence value and operation inventory | Source golden, pure/request parser Hspec, metadata literal assertions |
| TypeScript parity | Canonical checked IR renderer | Contract generation tests and byte drift |
| Whole-Surface completeness and no undeclared operation | Private aggregate proof plus checked inventory | Temporary proof typecheck and generator completeness diagnostics |
| Action/Intent lane separation | Distinct token kinds and kind-indexed renderer | Lane-misuse compile failures |
| No raw/unchecked escape | Hidden bundle/evidence constructors and no re-indexing function | Raw-rebinding fixtures and typed-authority source guardrails |

Diagnostic expectations are an authoring interface. The pilot must directly pin
Roster Action missing, extra, reordered, wrong-presence, wrong-wire,
wrong-owner, and cross-operation errors. Errors name the compact operation,
owner, affected marker, and expected local contract shape; they must not print an
expanded `Surface ...` primitive list. Generator tests must also prove the
builder, metadata, pure parser, request parser, and TypeScript IR all resolve the
same operation and field list.

## Measurable Pilot Hypothesis

The comparison source is
`Config/nix/baselines/production-build/staging-ea144503-grill.json`, collected by
`production-build-profile`. Candidate evidence must use matching builder system,
GHC/Nix configuration, cores, configure flags, and derivation identity reporting.

The pilot has two blocking interface gates. Both Roster
`Generated.Action.hi` and `.dyn_hi` must fall by at least 75%, the minimum signal
that operation locality worked, and each resulting file must also be at most
16 MiB, the epic's installed-interface budget. A result between those gates
returns to the concrete-record alternative and does not approve rollout. The
total Roster interface subtree, complete app `.hi`/`.dyn_hi`, and app-lib self
size must decrease consistently with the Action reduction after accounting for
the compact foundation; the private proof contributes nothing to installed
size.

The memory hypothesis is at least a 10% reduction in builder-process peak RSS,
with no increase accepted as successful evidence. Wall time must not regress by
more than 5% under comparable configuration. These system metrics are secondary
to the hard installed-interface result and must be reported with cgroup memory
and swap delta rather than interpreted in isolation.

Generated TypeScript should be byte-identical. The focused Roster Action closure
must not acquire the private proof, registered Surface catalog, reflection of the
full Surface, or generator implementation. Missing either interface gate returns
to the concrete-record alternative even if one noisy memory or wall-time sample
improves.

## Integration Constraints

The Roster pilot is one atomic foundation/generated/caller slice. Existing named
facade operations may remain, but no Roster signature or implementation may
retain `SurfaceActionFields RosterSurface ...`, full-Surface metadata reflection,
or full-Surface request parsing. Other families may retain the old seam only
until #347; Roster receives no compatibility or dual-authority path.

Operation evidence, metadata, and private proof are generated from the same
checked IR and checked before any managed publication. Runtime callers import
only the compact foundation and feature facade. Full rollout may proceed only
after the Roster diagnostic, generator-authority, closure, TypeScript, and
profile evidence satisfies the pilot boundary.

## Rollback Boundary

Before #347 begins, the Roster pilot remains one revertible slice with no schema,
customer-data, route, or browser-contract migration. Missing the interface
threshold, weakening a compile guarantee, changing TypeScript without explicit
approval, or admitting proof/generator modules into caller closure blocks
rollout and requires complete pilot rollback. Do not retain both request seams;
a compiler-size miss returns to ADR 0006's concrete-record alternative.

## Reconciliation

Delete this workstream after #347 completes. Move implemented authoring rules and
verification commands into `Application/Helper/FrontendContract/Surface/README.md`;
retain ADR 0006 as rationale. GitHub remains the implementation and status
tracker.

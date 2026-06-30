# Bepis Runtime Facts Finalization

Status: active

Supersedes/finalizes: `bepis-component-pipelines.md`

Tickets:

- Epic: `ir-z0j1` - Finalize Bepis runtime facts architecture
- `ir-mwma` - Define single Bepis operation/fact root
- `ir-xz3b` - Make authorization helpers emit scope facts
- `ir-gt0e` - Make audit helpers emit audit facts
- `ir-glwa` - Make live invalidation helpers emit live facts
- `ir-ufjf` - Make response helpers emit response facts
- `ir-23gs` - Replace action wrappers with final `runBepis` fact runner
- `ir-39dg` - Big-bang migrate all controllers off legacy Bepis metadata
- `ir-amxj` - Replace architecture facts and gates with generated Bepis fact contracts
- `ir-asoq` - Add final Bepis architecture test suite
- `ir-lydg` - Reconcile final Bepis docs and archive superseded plan

## Intent

Finalize Bepis around one simple runtime-fact model. Developers should write
normal IHP controller code plus Bepis-owned helpers. Those helpers emit typed
`BepisFact` values as a side effect of doing real work, and `runBepis` collects
those facts for telemetry, tests, development diagnostics, and deterministic
architecture reports.

This is deliberately simpler than the transitional pipeline/evidence model:
there is no manual evidence threading and no descriptive pipeline labels. A fact
exists because the helper that performed the effect emitted it.

```text
Bepis helper performs effect -> emitBepisFact -> collector + telemetry + tests/architecture
```

## Final Architecture Rule

There is one root concept:

```haskell
data BepisFact
    = BepisActionFact BepisActionFact
    | BepisScopeFact BepisScopeFact
    | BepisAuditFact BepisAuditFact
    | BepisLiveFact BepisLiveFact
    | BepisResponseFact BepisResponseFact
```

And one internal emission boundary:

```haskell
emitBepisFact :: BepisFact -> IO ()
```

`emitBepisFact` is not ordinary application code. It is the Bepis/telemetry
boundary. It should:

1. append the typed fact to the current request/action-local collector;
2. emit low-cardinality OpenTelemetry attributes or span events;
3. expose captured facts to tests and optional development artifacts.

OTel is a sink, not the source type. `BepisFact` remains typed Haskell data so
facts are testable without a collector/exporter and are not lost to sampling.

## Non-Negotiables

- Keep IHP as the outer framework boundary: route parsing, `Controller`
  instances, `beforeAction`, request context, HSX, QueryBuilder, generated types,
  and IHP response mechanics remain framework-owned.
- Bepis owns app semantics inside that lifecycle through `runBepis`, Bepis
  helpers, typed facts, and Haskell-generated contracts.
- Developers must not manually attach facts that merely describe intended
  behavior. Facts are emitted by helpers that actually perform effects.
- Do not keep `BepisMutationSpec`, standalone descriptive pipeline components,
  mutation drift modes, or regex-based semantic inference.
- Source scanners may locate actions/usages and forbid legacy tokens. They must
  not infer scope/audit/live/response semantics from source text.
- The final code should be boring to use. Controller authors should call normal
  Bepis helpers; fact collection should be automatic.

## Target Runtime Shape

A final action should read like normal controller code:

```haskell
action currentAction@ApproveTimesheetEntryAction { timesheetEntryId } =
    runBepis currentAction BepisMutationOperation do
        ensureManagerRole
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId

        _ <- approveTimesheetEntryMutation weekOffset timesheetEntry

        if isHtmxRequest
            then respondWithTimesheetDaySectionUpdate ...
            else redirectToPath ...
```

Facts are emitted by helpers:

- `runBepis` emits action/controller facts and opens the fact collector;
- authorization helpers emit scope facts only after successful checks;
- audit/version helpers emit audit facts only after successful writes;
- live invalidation helpers emit live facts only after actual invalidation;
- response helpers emit response facts when they perform the response.

No final action should contain calls like:

```haskell
scopedToCurrentVenue
scopedToRosterWeek
auditedAs
fromLiveMutationResult
respondsWithFragments
respondsWithRedirect
respondsWithJson
```

## Planned Fact Types

### Root/collector types

- `BepisFact` - sum of all emitted Bepis runtime facts.
- `BepisFactSet` - request/action-local collection of facts.
- `BepisFactContext` - internal `runBepis` collector context.
- `BepisOperationKind` - page, form, fragment, dialog, mutation, JSON,
  integration, export.
- `BepisOperationContext` - action name, operation kind, controller policy, and
  request/action metadata safe for telemetry.

### Action facts

Produced by `runBepis`:

- `BepisActionFact`
  - action constructor/name;
  - operation kind;
  - controller policy when available.

### Scope facts

Produced by authorization/scope helpers after successful checks:

- authenticated user;
- current venue;
- venue writable;
- role checks: owner, manager, staff/admin as appropriate;
- support/founder access;
- record-in-current-venue / request-derived id scope validation.

### Audit facts

Produced by audit/version/domain-event helpers after successful writes:

- audit event recorded;
- authentication audit recorded;
- version event recorded;
- target table/category and event type as low-cardinality text;
- source channel where relevant.

### Live facts

Produced by live invalidation helpers after actual touched-resource
invalidation/planning/broadcast:

- invalidation label;
- touched resource count;
- expanded resource count;
- planned scope count;
- planned fragment count;
- mechanism, e.g. websocket fragment refetch;
- actor-client/self-echo behavior if available.

`LiveMutationResult` alone is not a final live fact. The live fact is produced
by the invalidation helper that actually runs.

### Response facts

Produced by helpers that actually send the actor response:

- full HTML;
- HTMX fragment/OOB;
- dialog;
- redirect;
- JSON;
- file/export.

## Telemetry Boundary

`emitBepisFact` is also the telemetry boundary. Keep this split:

```text
BepisFact = typed semantic fact
Telemetry = sink/transport for observations
```

Telemetry should receive:

- low-cardinality action-span attributes for summaries, e.g. fact counts,
  operation kind, response kind, whether audit/live facts occurred;
- span events for detail, e.g. audit event type, live invalidation label, planned
  fragment count.

Avoid high-cardinality IDs or raw payloads in attributes. Tests and local debug
artifacts can inspect full typed facts without relying on OTel collection.

## Legacy Deletion List

The implementation is not complete until these are gone from committed runtime
code and architecture generators:

- `BepisMutationSpec`;
- feature-specific mutation spec values such as `timesheetEntryMutationSpec`;
- action wrapper signatures that require mutation specs;
- `auditedAs`;
- `scopedToCurrentUser`, `scopedToCurrentVenue`, `scopedToRosterWeek`,
  `scopedToSupport` as standalone labels;
- `fromLiveMutationResult`;
- `respondsWithFragments`, `respondsWithRedirect`, `respondsWithJson` as
  standalone descriptive labels;
- mutation drift guard modes/messages such as `BEPIS_MUTATION_DRIFT_*`;
- source regex that infers audit/scope/live/response semantics;
- generated fact fields whose semantics come from source regex rather than
  typed facts/contracts.

Final gates should include deterministic no-legacy checks for these names, with
exceptions only for archived/superseded documentation when explicitly allowed.

## Implementation Order

1. **Root model and telemetry boundary**
   - Add `Application.Bepis.Fact` or equivalent.
   - Define `BepisFact`, fact subtypes, `BepisFactSet`, `BepisOperationKind`,
     `BepisOperationContext`, and `emitBepisFact`.
   - Implement request/action-local fact collection and OTel emission.
   - Generate contract JSON from these typed values.

2. **Scope facts from authorization helpers**
   - Update Bepis/controller access helpers so successful checks emit scope
     facts.
   - Keep call sites simple; do not return facts unless a test/helper needs a
     captured result.

3. **Audit facts from audit/version helpers**
   - Update audit and version helpers to emit audit facts after DB writes.
   - Representative tests must assert both DB rows and captured facts.

4. **Live facts from invalidation helpers**
   - Update `invalidateTouchedResources*` to emit live facts after actual
     expansion/planning/broadcast.
   - Include counts/details safe for telemetry and tests.

5. **Response facts from response helpers**
   - Add/standardize Bepis response helpers that emit response facts at the
     response boundary.
   - Feature response helpers should use these, not standalone labels.

6. **Final `runBepis` action API**
   - Replace separate wrapper families with one runner plus an operation kind.
   - `runBepis` opens the collector, emits action fact, runs the IHP action body,
     summarizes facts to telemetry, and optionally enforces narrow safety checks.

7. **Big-bang controller migration**
   - Migrate all 175 handlers to the final API.
   - Delete mutation spec values and transitional pipeline helpers in the same
     migration, not as future cleanup.

8. **Architecture generator/gate cleanup**
   - Architecture facts consume generated Bepis fact/operation contracts.
   - Remove regex semantic inference for Bepis scope/audit/live/response.
   - Keep source scans only for finding actions/runner calls and no-legacy
     checks.

9. **Final tests**
   - Add tests for fact collection, OTel summarization, generated contract shape,
     representative controller paths, no-legacy tokens, and final architecture
     gates.

10. **Docs reconciliation**
    - Move durable final rules into local specs/AGENTS docs.
    - Mark transitional pipeline wording as superseded/archive-only.

## Verification

Each logical chunk should run:

```bash
bash ./bin/in-env typecheck
bash ./Config/nix/scripts/architecture/check-fresh
```

Focused chunks should run relevant Hspec. Final verification must include:

- typecheck;
- strict architecture gate;
- generated contract check/golden test;
- representative controller tests for page, fragment, dialog, mutation, JSON,
  export, and integration actions;
- audit fact tests that also assert DB audit/version rows;
- live fact tests that also assert live-update version/invalidation behavior;
- response fact tests that also assert actual response status/body/headers;
- OTel sample showing Bepis fact summaries/events on the action span;
- no-legacy token check.

## Exit Criteria

This workstream exits only when:

- `BepisFact`/`emitBepisFact` is the single semantic fact boundary;
- Bepis facts are emitted automatically by helpers that perform actual effects;
- all controllers/actions use the final `runBepis` API;
- legacy mutation specs, descriptive pipeline components, and drift guards are
  deleted;
- architecture facts no longer infer Bepis semantics from regex;
- strict gates and focused tests pass;
- docs describe the final clean architecture with no legacy fallback.

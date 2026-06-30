# Bepis Effect Evidence Finalization

Status: active

Supersedes/finalizes: `bepis-component-pipelines.md`

Tickets:

- Epic: `ir-z0j1` - Finalize Bepis effect-evidence architecture
- `ir-mwma` - Define single Bepis operation and evidence root
- `ir-xz3b` - Make authorization helpers produce scope evidence
- `ir-gt0e` - Make audit helpers produce audit evidence
- `ir-glwa` - Make live invalidation helpers produce realtime evidence
- `ir-ufjf` - Make response helpers produce response evidence
- `ir-23gs` - Replace action wrappers with final Bepis runner API
- `ir-39dg` - Big-bang migrate all controllers off legacy Bepis metadata
- `ir-amxj` - Replace architecture facts and gates with generated evidence contracts
- `ir-asoq` - Add final Bepis architecture test suite
- `ir-lydg` - Reconcile final Bepis docs and archive superseded plan

## Intent

Finalize the Bepis architecture around one root operation/evidence model. Bepis
semantics must be produced by the same helpers that actually perform effects:
authorization produces scope evidence, audit helpers produce audit evidence, live
invalidation helpers produce realtime evidence, and response helpers produce
response evidence.

This workstream intentionally removes the transitional legacy layer. Do not keep
`BepisMutationSpec`, standalone descriptive mutation evidence components, drift
warning modes, or semantic regex inference as permanent architecture.

## Non-Negotiables

- Keep IHP as the outer framework boundary: route parsing, `Controller`
  instances, `beforeAction`, request context, HSX, QueryBuilder, generated types,
  and IHP response mechanics remain framework-owned.
- Bepis owns the app semantics inside that lifecycle through one root model.
- Evidence is only valid when produced by the helper that performed the effect.
- No final code path may require both legacy descriptive metadata and new
  evidence.
- Generated architecture facts may use source scans to locate actions/usages or
  forbid legacy tokens, but not to infer Bepis semantics such as audit, scope,
  realtime, or response intent.
- Do not add another parallel metadata layer to bridge the migration.

## Target Model

The exact names may change during implementation, but the shape should converge
on one root type family similar to:

```haskell
data BepisOperation action result = BepisOperation
    { operationAction     :: action
    , operationKind       :: BepisOperationKind
    , operationController :: BepisControllerPolicy
    , operationRun        :: BepisProgram result
    }

data BepisProgram result = BepisProgram
    { programRun :: IO (BepisOutcome result)
    }

data BepisOutcome result = BepisOutcome
    { outcomeValue    :: result
    , outcomeEvidence :: BepisEvidenceSet
    }

data BepisEvidence
    = BepisScopeEvidence BepisScopeFact
    | BepisAuditEvidence BepisAuditFact
    | BepisLiveEvidence BepisLiveFact
    | BepisResponseEvidence BepisResponseFact
```

The important invariant is not the names; it is the ownership rule:

```text
actual effect helper succeeds -> returns/emits evidence -> root operation runner records evidence
```

## Evidence Producers

### Scope / authorization

Final scope evidence must come from helpers that actually authorize:

- current user / current venue checks;
- manager/admin/support checks;
- record-in-current-venue checks;
- request-derived id scope validation.

Standalone calls such as `scopedToCurrentVenue` are not final architecture. They
may only exist during an uncommitted implementation step and must not remain.

### Audit

Final audit evidence must come from helpers that actually write audit/version or
domain-event records:

- `recordAuditEvent`;
- `recordCurrentUserAuditEvent`;
- `recordUserAuthenticationAuditEvent`;
- important version helpers such as timesheet entry version writes.

Standalone calls such as `auditedAs` are not final architecture.

### Realtime/live

Final live evidence must come from helpers that actually perform touched-resource
invalidation/planning/broadcast:

- `invalidateTouchedResources`;
- `invalidateTouchedResourcesWithoutContext`;
- eventual typed surface actor response helpers if they trigger live refetch
  behavior.

`LiveMutationResult` by itself proves touched resources, not broadcast. Final
realtime evidence should distinguish touched resources, expanded resources,
planned scopes/fragments, and broadcast outcome where available.

Standalone calls such as `fromLiveMutationResult` are not final architecture.

### Response

Final response evidence must come from the helper that actually responds:

- redirects;
- full HTML render;
- HTMX fragments/OOB swaps;
- dialogs;
- JSON;
- files/exports.

Standalone calls such as `respondsWithFragments`, `respondsWithRedirect`, or
`respondsWithJson` are not final architecture.

## Legacy Deletion List

The implementation is not complete until these are gone from committed code:

- `BepisMutationSpec`;
- feature-specific mutation spec values such as `timesheetEntryMutationSpec`;
- wrapper signatures that require mutation specs;
- `auditedAs`;
- `scopedToCurrentUser`, `scopedToCurrentVenue`, `scopedToRosterWeek`,
  `scopedToSupport` as standalone evidence labels;
- `fromLiveMutationResult`;
- `respondsWithFragments`, `respondsWithRedirect`, `respondsWithJson` as
  standalone descriptive labels;
- mutation drift guard modes and messages;
- source regex that infers audit/scope/realtime/response semantics.

Final gates should include `rg`/deterministic no-legacy checks for these names.

## Implementation Order

1. Define the root operation/evidence model and generated contract vocabulary.
2. Change authorization helpers to produce scope evidence after successful
   checks.
3. Change audit/version helpers to produce audit evidence after successful
   writes.
4. Change live invalidation helpers to produce realtime evidence after actual
   invalidation/planning/broadcast.
5. Change response helpers to produce response evidence at the response boundary.
6. Replace separate action wrappers with the final root runner API.
7. Big-bang migrate every controller/action away from legacy metadata.
8. Replace architecture facts/gates so semantics come from generated evidence
   contracts and no-legacy checks, not regex inference.
9. Add tests that lock the final model and prevent legacy reintroduction.
10. Reconcile docs and mark transitional wording as superseded.

## Testing And Verification

Each logical implementation chunk should run:

```bash
bash ./bin/in-env typecheck
bash ./Config/nix/scripts/architecture/check-fresh
```

Relevant chunks should also run focused Hspec. The final gate must include:

```bash
rg 'BepisMutationSpec|auditedAs|scopedTo(CurrentUser|CurrentVenue|RosterWeek|Support)|fromLiveMutationResult|respondsWith(Fragments|Redirect|Json)|BEPIS_MUTATION_DRIFT' Application Web scripts Config .tickets docs
```

with only historical/superseded documentation exceptions if explicitly allowed.

Final verification should include:

- unit tests for root operation/evidence pure behavior;
- focused controller tests for representative page, fragment, dialog, mutation,
  JSON, export, and integration actions;
- tests proving audit helpers return evidence after writes;
- tests proving live invalidation helpers return evidence after invalidation;
- tests proving response helpers return/record response evidence;
- generated contract JSON shape/golden test;
- architecture gate with strict no-legacy checks;
- one OTel trace sample showing final evidence attrs on an action span.

## Exit Criteria

This workstream exits only when:

- one root Bepis operation/evidence model owns all app semantics;
- evidence is produced by actual effect helpers;
- all controllers/actions use the final runner API;
- legacy mutation specs and descriptive evidence components are deleted;
- architecture facts no longer infer Bepis semantics from source regex;
- strict gates and focused tests pass;
- durable docs describe the final no-legacy rules.

# Bepis Runtime Facts Finalization

Status: implemented

Finalizes/supersedes: `bepis-component-pipelines.md`

## Final Contract

Bepis now uses one runtime-fact model. Developers write normal IHP controller
code plus Bepis-owned helpers. Those helpers emit typed `BepisFact` values as a
side effect of doing real work, and `runBepis` collects those facts for
telemetry, tests, development diagnostics, and deterministic architecture
reports.

```text
Bepis helper performs effect -> emitBepisFact -> collector + telemetry + tests/architecture
```

## Root Types

The root semantic boundary is:

```haskell
data BepisFact
    = BepisActionFactValue BepisActionFact
    | BepisScopeFactValue BepisScopeFact
    | BepisAuditFactValue BepisAuditFact
    | BepisLiveFactValue BepisLiveFact
    | BepisResponseFactValue BepisResponseFact
```

The internal emission boundary is:

```haskell
emitBepisFact :: BepisFact -> IO ()
```

`emitBepisFact` appends the typed fact to the current request/action-local
collector, emits low-cardinality OpenTelemetry attributes or span events, and
makes captured facts available to tests.

OTel is a sink, not the source type. `BepisFact` remains typed Haskell data so
facts are testable without an exporter and are not lost to trace sampling.

## Controller Shape

Controller actions keep the normal IHP shape and delegate through `runBepis`:

```haskell
action currentAction@ApproveTimesheetEntryAction { timesheetEntryId } =
    runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        _ <- approveTimesheetEntryMutation weekOffset timesheetEntry
        respondWithTimesheetDaySectionUpdate ...
```

## Fact Producers

- `runBepis` emits action facts and opens the fact collector.
- Authorization/scope helpers emit scope facts only after successful checks.
- Audit/version helpers emit audit facts only after successful writes.
- Live invalidation helpers emit live facts after actual invalidation planning
  and broadcast work.
- Response helpers emit response facts when they perform the response.

Application code should not add parallel labels that merely describe intended
behavior. If a semantic event matters, put the fact emission in the helper that
actually performs the event.

## Architecture Tooling

Generated Bepis architecture contracts come from
`Application.Bepis.Architecture` through `architecture-contracts`.

Source scanners may:

- locate controller actions and `runBepis` calls;
- count source references and call sites;
- enforce no-legacy/no-missing-runner checks.

Source scanners must not infer Bepis scope, audit, live, or response semantics
from source regex. Those semantics come from generated Haskell contracts,
helper-emitted facts, and runtime telemetry/fact artifacts.

## Verification

Current final checks:

```bash
bash ./bin/in-env typecheck
bash ./Config/nix/scripts/architecture/check-fresh
bash ./bin/in-env hspec-test --match "Mutation boundary guard"
bash ./bin/in-env hspec-test --match "TimesheetsController/manager review actions bump"
bash ./bin/in-env hspec-test --match "TimesheetsController/writes an audit event when approving"
```

The architecture convention query reports 18 migrated controllers and 175
`runBepis` handlers with no convention violations.

## Exit Criteria

This workstream is complete when:

- `BepisFact`/`emitBepisFact` is the single semantic fact boundary;
- Bepis facts are emitted automatically by helpers that perform actual effects;
- all controllers/actions use `runBepis`;
- transitional descriptive metadata APIs are removed;
- architecture facts no longer infer Bepis semantics from regex;
- strict gates and focused tests pass;
- durable docs describe the final clean architecture with no legacy fallback.

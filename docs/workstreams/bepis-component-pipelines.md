# Bepis Component Pipeline Refactor

Status: implemented

Finalization note: this transitional stream is superseded for future work by
`bepis-effect-evidence-finalization.md`, which removes legacy mutation specs and
requires evidence to be produced by actual effect helpers.

Tickets:

- Epic: `ir-si7h` - Bepis component pipeline refactor
- `ir-bi2e` - Remove Bepis action name string literals
- `ir-6fzq` - Emit Bepis architecture contracts from typed Haskell values
- `ir-kd68` - Design and implement Bepis mutation pipeline core
- `ir-bhbi` - Migrate one representative mutation to pipeline evidence
- `ir-9iew` - Add mutation audit/realtime drift guards during transition
- `ir-h91z` - Unify Bepis component pipeline documentation

## Intent

The current Bepis action boundary is app-wide and enforceable by deterministic
architecture gates, but some semantics still live as descriptive metadata beside
implementation. This workstream moves the important parts toward typed values,
component pipelines, and runtime/effect evidence.

The live-surface descriptor system is the exemplar: start with a typed core,
attach capabilities with `|>`, and lower/render/run at a boundary. Mutations,
action contracts, permission/scope evidence, audit, realtime invalidation, and
response shape should follow the same style where it improves correctness and
readability.

## Design Principles

- Keep IHP as the outer framework boundary: routes, `Controller` instances,
  request context, HSX, QueryBuilder, and response helpers remain IHP-native.
- Bepis owns app semantics inside the IHP lifecycle: controller policy, action
  kind, mutation effects, live scopes, audit/realtime evidence, response intent,
  generated architecture facts, and telemetry labels.
- Prefer typed values and generated contracts over string matching or parallel
  metadata.
- Prefer pipeline components when a capability is optional/composable and should
  be visible at the call site.
- Prefer evidence tokens/results when the system must prove an effect happened,
  such as audit, scope authorization, live invalidation, or response shape.
- Use typeclasses for intrinsic behavior shared by a family of types; avoid
  typeclass instances that hide business policy away from the mutation/action
  call site.
- Keep architecture diagrams and queries as views over generated facts, not a
  separate source of truth.

## Current State

Implemented baseline:

- all controllers use `bepisBeforeAction`;
- all actions use a Bepis action wrapper;
- all mutation wrappers require a `BepisMutationSpec`;
- strict architecture gate passes for all controllers/actions;
- wrapper metadata is derived from `Application/Bepis/Action.hs` typed wrapper
  definitions rather than a duplicated JavaScript map;
- mutation policy labels are derived from `Application/Bepis/Mutation.hs` text
  conversion functions;
- feature-specific mutation specs exist for high-risk areas.

Implemented changes in this stream:

- action wrappers derive labels from the bound IHP action value;
- Bepis architecture contracts are emitted from typed Haskell values through
  `Application.Bepis.Architecture` and `architecture-contracts`;
- the Bepis mutation pipeline core carries scope, audit, realtime, and response
  evidence;
- `ApproveTimesheetEntryAction` proves the pipeline on a real audited realtime
  mutation;
- architecture facts detect pipeline evidence and transition drift warnings.

Remaining weakness after this stream:

- most mutation actions still use legacy `BepisMutationSpec` as fallback;
- Node architecture tooling still scans source to locate usage sites;
- strict mutation drift mode intentionally fails until more legacy actions expose
  audit/realtime evidence or documented exceptions.

## Target Shape

### Actions

Previous:

```haskell
action ShowRosterWeekAction { weekOffset } =
    bepisPageAction "ShowRosterWeekAction" do
        ...
```

Implemented:

```haskell
action action@ShowRosterWeekAction { weekOffset } =
    bepisPageAction action do
        ...
```

The action label should be derived from the actual IHP action value, not a
manually maintained string.

### Mutation Pipeline

Previous:

```haskell
action CreateRosterSlotAction { rosterDayId } =
    bepisMutationAction "CreateRosterSlotAction" rosterWeekMutationSpec do
        ...
```

Implemented representative pattern:

```haskell
action currentAction@ApproveTimesheetEntryAction { timesheetEntryId } =
    bepisMutationAction currentAction timesheetEntryMutationSpec do
        ...
        newMutation (approveTimesheetEntryMutation weekOffset timesheetEntry)
            |> scopedToCurrentVenue
            |> auditedAs "timesheet_approved"
            |> fromLiveMutationResult "timesheet.approve"
            |> respondsWithFragments "timesheet-day-section"
            |> respondsWithRedirect "timesheet-week"
            |> runBepisMutationPipeline
```

The pipeline should produce typed evidence/results for:

- authorized scope;
- audit/version/domain-event effect;
- realtime/live-resource invalidation effect;
- actor response shape.

Architecture facts should prefer the pipeline/evidence result over legacy
`BepisMutationSpec` metadata.

### Generated Contracts

Bepis architecture contracts should be emitted from typed Haskell values where
possible. Node tooling may still scan source to locate usages, but vocabularies
and contract metadata should come from generated Haskell-owned JSON artifacts.

Examples:

- action wrapper contracts;
- action kind vocabulary;
- response kind vocabulary;
- controller policy vocabulary;
- mutation pipeline component contracts;
- mutation policy/evidence vocabulary.

## Scope

In scope:

- Bepis action wrapper API changes;
- generated architecture contract artifacts;
- mutation pipeline core types and components;
- one representative mutation migration;
- transition drift checks for legacy `BepisMutationSpec` actions;
- docs and local agent rules for the pipeline pattern.

Out of scope for this workstream:

- replacing IHP routing/controller dispatch;
- broad custom effect monad unless a ticket proves it is needed;
- rewriting all existing mutations in one pass;
- making diagrams source of truth.

## Integration Points

- `Application/Bepis/Action.hs`
- `Application/Bepis/Controller.hs`
- `Application/Bepis/Mutation.hs`
- `Application/Bepis/Response.hs`
- `Application/Helper/LiveSurface*.hs`
- `Application/Helper/LiveResource.hs`
- `Application/Helper/Audit.hs`
- `Web/LiveSurfaceRegistry.hs`
- `Web/LiveResourceInvalidation.hs`
- `scripts/architecture/*.mjs`
- `Config/nix/scripts/architecture/check-fresh`

## Verification Plan

Each implementation slice should run focused checks plus the strict architecture
gate:

```bash
bash ./bin/in-env typecheck
bash ./Config/nix/scripts/architecture/check-fresh
architecture_query conventions failOnViolations=true requireAllControllers=true
```

Representative mutation migration should also run the relevant focused Hspec
controller/module tests and, when practical, an OTel profile trace query.

## Exit Criteria

This workstream is complete because:

- action wrappers derive labels from action values rather than string literals;
- Bepis contract vocabularies are emitted from typed Haskell values;
- a representative mutation is implemented through the new pipeline and returns
  typed scope/audit/realtime/response evidence;
- architecture facts prefer generated contract/evidence facts over descriptive
  metadata for migrated actions;
- transition drift checks cover legacy spec-backed mutations;
- local docs/specs describe the pattern and anti-patterns;
- strict architecture gates and focused tests pass.

## Documentation Updates Needed As Slices Land

- `docs/architecture/README.md` - architecture tooling and fact provenance.
- `Application/Helper/LiveSurface.COOKBOOK.md` - shared pipeline-component
  vocabulary if surface rules change.
- `Application/Helper/LiveUpdate.SPEC.md` - mutation/live-resource evidence
  flow once implemented.
- `Web/Controller/AGENTS.md` - action wrapper and mutation pipeline rules for
  controller authors.
- `Application/AGENTS.md` or nearest subsystem docs - mutation module rules for
  audit/realtime/scope evidence.

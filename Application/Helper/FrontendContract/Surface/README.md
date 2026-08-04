# FrontendSurface Authoring Guide

`Application.Helper.FrontendContract.Surface` is the typed contract system for
server-rendered, interactive feature surfaces. Use it instead of parallel DTO
catalogs, mount protocols, invalidation registries, or projection caches.

## Authority And Extension Seams

`Surface.Registry` contains `RegisteredFrontendSurfaces`. `Surface.Reflect`
evaluates any closed Surface DSL; `Surface.Contracts` binds that evaluator to the
production registry and validates the single checked `SurfaceContractIR`.
Runtime rendering, generated TypeScript/Haskell, compile-time values, and semantic
architecture facts consume that checked model directly.

Feature declarations live in focused modules beside the DSL. Add a production
surface by:

1. defining its type-level `Surface` spec with `Surface.DSL`
2. registering it in `RegisteredFrontendSurfaces`
3. implementing one `SurfaceImpl` from marker-indexed values
4. rendering mounts/fragments/actions/intents through runtime helpers
5. emitting feature-owned typed resources from mutations
6. regenerating contracts/adapters and adding focused tests

Test/diagnostic fixtures stay under `Test/` and must not enter the production
registry. Extend the existing DSL/reflection/checked-IR path; do not add another
evaluator or name-dispatched generator.

## Contract Vocabulary

- **Surface**: independently mounted feature UI owner.
- **Scope**: authorized logical data slice, not a page or route.
- **Mount**: one concrete Surface/scope occurrence, identified by a mount key.
- **Fragment**: server-rendered target with typed identity, target, GET URL, and
  protection; `Live` marks passive/reconnect participation.
- **Resource**: semantic business data changed by a mutation.
- **Action / Intent**: Haskell-owned HTMX request metadata and exact field
  contracts; intents commit interaction sessions.
- **MountState**: server-only view state, separate from subscription identity.
- **Contained Surface**: independently mounted child declared inside a parent
  fragment.
- **Disposable layer/session**: temporary browser-owned UI constrained by
  generated interaction contracts.

Fields use the closed wire universe in `Core`; serialize narrow browser DTOs,
not domain models. Browser DTO reachability and codec direction are explicit.
Shared declaration bundles are type aliases composed through approved DSL
helpers, not secondary registries.

## Marker-Indexed Values And Requests

Use `Surface.Values` and focused feature facades. Marker-indexed builders enforce
owning Surface, declaration order, field presence, wire type, and Haskell type.
Raw `SurfaceFields` constructors stay hidden; optional and nullable semantics
remain distinct. Scope, fragment, and resource identities are opaque outside
their focused construction/matching seams.

Actions and intents declare browser-submitted fields plus typed HTMX method,
selector, trigger, swap, and synchronization values. IHP route context remains
in route builders. Raw HTMX values require a non-empty checked reason. Render
forms/links/buttons with runtime helpers and parse requests with the generated
operation parser from the feature-owned Action/Intent facade. Required,
optional, nullable, and repeated fields are parsed exactly; attach structured
errors to normal validation rather than defaulting required values.

Successful resource-backed mutations use actor resource refresh planning;
requester-local non-resource workflows may select actor fragments directly.
Validation failures return their form/dialog fragment. Successful migrated
mutations do not return authoritative business OOB HTML; OOB is reserved for
extras such as toasts and dialog cleanup.

## Mounts, Authorization, And Live Dependencies

Build one-step `SurfaceImpl` values with declaration-owned scope, mount state,
mounted fragments, URLs, and protection. Render through
`renderFrontendSurfaceMount`; never handwrite mount attrs. The exact browser
mount envelope contains only Surface identity, scope key, mount key, fragment
descriptors, and optional subscription. Server state and derived lists stay out
unless a browser consumer is declared.

Every scope declares exactly one closed authorization policy (or explicit
public/test-only `NoAuth`) with its required UUID fields. Fragment GET routes
still authorize every identity field and visibility rule. Runtime authorization
comes from checked registered metadata, never policy text or feature fallbacks.

A passive fragment declares one mode:

- `DependsOn` maps typed resource fields from scope/fragment fields.
- `ResyncOnly` has no passive business-resource dependency.

Mutation code emits concrete values through `Surface.<Feature>.Resource`.
`Surface.DependencyPlanner` matches resources against mounted/subscribed keys,
coalesces exact duplicates, and uses typed containment to suppress a selected
child when its matching ancestor is selected. Siblings and differently
parameterized descendants remain independent. Broad domain fanout is expanded
to concrete resources in a feature-owned producer/helper, not a custom planner
hook.

Child mounts remain independent. Browser reconciliation follows current DOM
recursively so inserted mounts initialize, removed descendants dispose, and
subscriptions equal the mounted scope set.

## Interaction Ownership

Surface specs own generated refs, opaque dynamic keys, disposable layers,
sessions/effects, conflict policy, and DOM-owned intent forms. TypeScript may
compare/forward opaque keys and mutate declared disposable layers; it must not
parse keys, construct mutation URLs, alter server business DOM, or invent
feature names/fields.

Prefer shared typed aliases for drag/drop and other repeated interaction shapes.
The shared SidePanel alias declares root, main, panel, toggle, label, and closed
visibility state while each feature retains panel content and authorization.
Effects come from the closed semantic IR and clean up on every terminal path.
Concrete mounts derive IDs/targets/forms from the mount key; runtime lookup stays
inside the nearest owning mount and does not cross nested mounts. See
`Application/Helper/Interaction.SPEC.md` for the cross-module interaction
contract.

## Generated Adapter Boundary

`Surface.HaskellAdapter.Core` and focused renderers derive Resource, Live,
Action, and Intent modules from checked declarations. Exactly one checked home is registered
for every eligible declaration. Private `.Generated.Resource`,
`.Generated.Live`, `.Generated.Action`, and `.Generated.Intent` modules remain
behind matching curated feature facades. Feature code never imports generated
internals from another family or reconstructs mechanical builders/matchers.

The all-kind writer validates every lane and physical path, renders/formats/
typechecks a complete temporary set, then publishes atomically. Weeder roots only
declaration-complete private Resource/Live APIs; generated request modules and
curated facades remain under ordinary reachability.

## Architecture Facts And Diagrams

`Surface.Architecture` renders semantic facts from checked production IR. Use
deterministic project commands rather than prose inventories:

```bash
bash ./bin/in-env architecture-facts
bash ./bin/in-env architecture-surface-request-closure --print-modules
printf '%s\n' '{"name":"generated-contracts","args":{"target":"roster"}}' \
  | bash ./bin/in-env architecture-query
```

The generated-contracts query shows the reflection pipeline, per-Surface
semantics, generated contracts, and browser consumers. Source/module scanners
and telemetry remain authoritative for imports, routes, schema, and runtime
traces.

## Verification Authority

Checked-IR/runtime round trips own semantics; compile-fail fixtures own impossible
marker/field/wire/lane combinations; byte-identical generation checks own output;
architecture checks own facade closure; narrow guardrails own retired vocabulary
and forbidden imports. Do not mirror these with source-substring inventories.

```bash
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env frontend-surface-adapters-check
bash ./bin/in-env frontend-surface-compile-fail-check
bash ./bin/in-env frontend-surface-guardrails
bash ./bin/in-env typecheck
bash ./bin/in-env frontend-check
bash ./bin/in-env hspec-test --match "FrontendSurface" --match "SurfaceDependency" --match "SurfaceGuard"
```

Run feature-specific Hspec and E2E when changing a concrete Surface.

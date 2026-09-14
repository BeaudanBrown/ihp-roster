# FrontendSurface Authoring Guide

`Application.Helper.FrontendContract.Surface` owns the typed contract for mounted,
server-rendered interactive surfaces. Use it instead of adding parallel browser
DTO catalogs, mount protocols, invalidation registries, handwritten semantic
`data-bepis-*` attributes, or feature-specific interaction transports.

This guide defines ownership and extension procedure. Read the focused durable
contracts when changing their concerns:

- `Application/Helper/FrontendContract/README.md` — global browser-contract and
  generated-output ownership;
- `Application/Helper/Interaction.SPEC.md` — disposable interaction lifecycle,
  intent commit, and browser/server authority;
- `Application/Helper/LiveUpdate.SPEC.md` — authorization, resources, durable
  invalidation, planning, and fragment refresh;
- `docs/adr/0006-operation-local-frontend-contract-evidence.md` — why request
  callers use generated operation-local evidence.

Current declarations, generated interfaces, and consumers are discoverable with
the source-derived commands under [Architecture navigation](#architecture-navigation).
Do not copy their inventories or counts into prose.

## Ownership Map

The contract pipeline has one authority at each stage:

- `Surface.DSL` defines the promoted vocabulary. Focused feature declarations
  live under `Surface/<Feature>.hs`; production roots are registered only by
  `Surface.Registry`.
- `Surface.Reflect` evaluates any closed Surface declaration. `Surface.Contracts`
  binds that evaluator to the production registry and validates one opaque
  `SurfaceContractIR`. `Surface.SemanticIR` contains checked interaction
  semantics.
- `Surface.Values`, `Surface.Resource`, `Surface.Live`, and `Surface.Request`
  own marker-indexed Haskell values, identities, and exact request parsing.
  `Surface.Runtime` owns mount and form rendering.
- `Surface.HaskellAdapter` generates mechanical Resource, Live, Action, and
  Intent modules. Private `.Generated.*` modules sit behind feature-owned
  curated facades.
- `Application.Helper.FrontendContract.Contracts` generates
  `frontend/ts/generated/contracts.ts`. That file and private generated Haskell
  modules are outputs; never edit them directly.
- `Surface.Architecture` emits semantic facts from checked IR. Deterministic
  checks and focused architecture queries own current topology and closure
  evidence.

Feature controllers, views, and domain modules retain authorization, route
construction, business validation, read models, rendered HTML, mutation effects,
and domain-shaped adapters. TypeScript retains generic browser/platform
mechanics only.

## Surface Shape And Composition

A production Surface is a closed type-level declaration built from nullary marker
types and promoted DSL primitives:

```haskell
data ExampleSurfaceName
data ExampleScope
data ExampleFragment
data VenueId
data AnchorDate

type ExampleSurface =
    Surface ExampleSurfaceName
        '[ Scope ExampleScope
            '[ Field VenueId 'WireUUID
             , Field AnchorDate 'WireDay
             ]
         , Fragment ExampleFragment '[] '[ 'Eager ]
         ]
```

A **Surface** is an independently mounted owner of scope, fragments, generated
contracts, and runtime values. A **Fragment** is a replaceable server-rendered
DOM target. A contained child Surface remains independent: it owns its scope,
authorization, fragments, protection, and subscription. Parent replacement may
remove nested mounts, so generic reconciliation must initialize inserted
children, dispose removed descendants, and avoid duplicate subscriptions for
surviving instances.

Use `MountState` only for server-side view state that is not subscription
identity or browser mount configuration. Do not expose it merely because the
server needs it. Every fragment has one typed `MountTarget`; views and mounted
descriptors derive the same target through marker-indexed helpers rather than
repeating IDs.

Shared declaration groups are type aliases composed with approved `Append` and
`Concat` helpers, not secondary registries. Reflection must have an explicit
instance for every supported constructor. Add vocabulary to the DSL,
reflection, checked IR, generation, and fixtures together; never add a second
evaluator or inspect GHC internals.

Test and diagnostic surfaces belong under `Test/` and remain outside
`RegisteredFrontendSurfaces`.

## Fields, Wires, DTOs, And Naming

Field bundles are declaration-ordered and marker-indexed. Construct them with
`noSurfaceFields`, `(&:)`, `surfaceField`, `surfaceOptionalField`, and
`surfaceNullableField`. Raw constructors stay hidden. Presence and wire shape
are separate:

- required fields must be present;
- optional fields may be omitted, with blank input mapping to `Nothing` at the
  request boundary;
- nullable fields must be present and may carry null;
- list, optional, nullable, reference, and closed/domain wires retain their
  nested Haskell source types.

Use `WireClosed value` for a finite registered Haskell authority. Persisted
finite domains use generated PostgreSQL enum types, not shadow ADTs.
`WireDomain value` is for an open text protocol whose owning domain supplies a
nominal `NominalText` codec. Do not serialize broad domain models through
Surface fields; project them into a narrow browser DTO or feature render model.

Plain Surface DTOs are server-only. Browser reachability and codec direction
must be explicit (`BrowserTypeDto`, guard, inbound, outbound, or bidirectional).
Generated inbound parsers are exact: missing, extra, or mistyped fields reject
the payload before browser effects. `WireUnknown` is not an escape hatch for
app-owned records.

Names derive from marker types through `Application.Helper.FrontendContract.Naming`.
Prefer descriptive markers and generated names. Surface names have no exact-name
override; reflection derives them from markers and checked IR validates naming
collisions in their owning namespaces.

Marker ownership is compile-time authority. A marker from another Surface, an
incomplete or reordered bundle, a wrong presence/wire/Haskell type, or a bundle
from another Action/Intent must remain a compile error. Keep focused diagnostic
expectations in
`Config/nix/scripts/frontend/surface-compile-fail-check` aligned when this
intentional authoring interface changes.

## Runtime Mounts And Rendering

A feature exposes runtime behavior through `SurfaceImpl spec`. Use
`mkSurfaceImplFromValues` to derive the Surface name, canonical scope identity,
exact scope/mount-state JSON, mounted fragments, and optional subscription from
marker-indexed values. Build fragment descriptors with
`frontendSurfaceMountedFragmentFor`; pass each dynamic fragment set directly or
through a feature-owned helper.

Render with `renderFrontendSurfaceMount`. The browser mount envelope is exact
and minimal: Surface identity, scope key, mount key, fragment descriptors, and
optional subscription. Each descriptor carries only semantic fragment key,
local target, URL, and protection. DOM/config disagreement or unknown fields are
invalid and must be diagnosed rather than coerced. Do not add server mount state,
derived resync lists, action catalogs, or feature fallbacks to the envelope.

Use the runtime lazy-fragment helpers so target identity, HTMX metadata, retry
behavior, and UI-region lifecycle remain typed and Haskell-owned. A custom
placeholder configuration may provide existing chrome, but it must not create a
second visual or lifecycle owner.

Server-rendered HTML is authoritative. Fragment GETs return the target node
itself. Browser code resolves only validated descriptors from the nearest
owning mount and must not infer URLs, targets, protection, or business meaning
from names, text, classes, or DOM position.

## Actions, Intents, And Forms

`Action` describes a Surface-owned request initiator. `Intent` describes the
committed form boundary for a declared interaction. Their fields are submitted
payload only; route IDs, venue context, pagination, and other URL state remain in
Haskell route builders.

Production callers use their feature-owned generated `Surface.<Feature>.Action`
or `.Intent` facade:

1. build the complete nominal field bundle with the generated operation builder;
2. obtain operation metadata from that same generated operation;
3. render it with `Surface.Runtime` form/link/control helpers and a Haskell-owned
   `FrontendSurfaceActionRoute` where applicable;
4. parse it in the controller with the matching generated exact parser;
5. attach structured transport failures to normal model validation.

Do not call generic Action/Intent constructors or parsers from production
features, handwrite operation field names, unwrap/re-index bundles, or reuse a
same-shaped bundle across operations. Operation-local nominal evidence is the
accepted interface; whole-registry equality is checked by private generated
proofs as described by ADR 0006.

Use typed HTMX methods, selectors, triggers, swaps, and synchronization recipes.
Raw HTMX values and `CustomHtmx` require a non-empty reason when the closed
vocabulary cannot express a value. Views combine typed request metadata with
normal routes; the DSL does not replace IHP routing.

Required parameters never recover through `paramOrDefault`. Optional, nullable,
list, malformed, and repeated inputs follow the declared parser semantics.
Controllers still treat every browser value as untrusted, validate venue and
record ownership, and enforce domain constraints and authorization.

Validation failures rerender the submitted form/dialog. Successful migrated
mutations do not return authoritative business fragments OOB: they report typed
resources for shared changes or explicit actor-local fragment keys only for
requester-local workflows, while OOB remains limited to extras such as dialog
cleanup and toasts.

## Interaction Contracts

Feature interaction names and relationships belong in the owning Surface.
Generated source, dropzone, activation, role, state, linked-highlight, sort, tab,
and session declarations feed minimal browser registries. Views attach them with
marker-indexed Haskell helpers.

Static ref names are generated. Dynamic keys are opaque server-rendered values:
the browser may compare or forward them but never parse them as authorization or
domain meaning. Concrete mutation forms remain Haskell-rendered DOM; mount JSON
is not a custom mutation transport. Generic interaction code fills only declared
intent fields and dispatches the generated trigger.

Effects use the closed semantic interaction IR. Required layers, options,
references, and effect placement are checked before generation. TypeScript
switches over generated closed unions exhaustively and owns only transient
browser mechanics/classes/state. Server DOM and native/ARIA state remain the
source of truth across reconciliation.

Use aliases from `Surface.Interaction` for common drag/drop session shapes rather
than rebuilding low-level declarations. Add a focused helper module when a
reusable typed rendering boundary is needed; do not expose raw attributes at
feature call sites.

Reusable global browser capabilities—overlays, toggles, pickers, ranges,
horizontal scrolling, passkeys, PWA install, and filters—are owned by focused
`Application.Helper.FrontendContract` roots, not by a feature Surface. Compose
them through generated roles and native state without importing one capability's
feature meaning into another. See the parent FrontendContract README and focused
view/runtime modules for those boundaries.

## Live Authorization And Resources

The complete live contract is in `Application/Helper/LiveUpdate.SPEC.md`; these
rules are mandatory at the Surface authoring seam:

- Every scope declares exactly one `Authorize policy` or explicit public/test
  `NoAuth`. Policy fields are exactly the required UUID fields consumed by that
  policy. Fragment routes independently enforce the same viewer authorization
  as full pages; browser keys are assertions, never authority.
- Live fragments select exactly one mode. `DependsOn` maps typed scope/fragment
  fields to declared Resources; `ResyncOnly` has no passive business dependency.
  Parameterize repeated fragments only when the key is also a natural resource
  and authorization boundary.
- Construct/match scope, fragment, and resource identity only through
  `Surface.Live`, `Surface.Resource`, or feature-owned generated facades. Do not
  import internal carriers, recover names/JSON by text, or add custom dependency
  hooks.
- A live-visible mutation commits business/domain/audit writes and durable typed
  resource invalidation through the atomic mutation boundary. Actor and passive
  planning share semantic keys and one dependency planner. Broad effects expand
  to concrete resources in the producer or a focused domain helper, not in the
  generic planner.
- Browser live code consumes generated keys and local descriptors. It does not
  add feature-specific subscribe/refetch/dedupe logic, transport URLs, fallback
  auth, or a second focus/DOM-diff owner.

A fragment request-context decorator may add only values encoded by a generated
browser-outbound DTO. It is tied to the concrete mount and cannot move business
calculation or filtering into TypeScript.

## Generated Haskell Adapter Contract

Mechanical adapters are generated from checked declarations, not handwritten
inventories. A feature family associates once with its Surface through
`AdapterFamilySurface`; kind-indexed homes select Resource, scope, fragment,
Action, and Intent declarations without repeating fields, presence, or wire
shape.

Generation must preserve these boundaries:

- every eligible production declaration has one validated typed home or a
  typed, non-empty, reason-bearing operation decision;
- Action and Intent remain distinct lanes even when marker names match;
- private generated modules import only the focused runtime seams allowed by
  guardrails and remain behind curated facades;
- Resource and Live generated APIs may be declaration-complete, while curated
  facades expose only semantic consumers;
- generated Action/Intent and handwritten modules remain under ordinary Weeder
  reachability;
- all adapter lanes render, format, typecheck, and validate as one staged set
  before publication or stale-file removal.

Do not edit `.Generated.*`, add a compatibility facade, retain partial generator
output, or expose generator/registry machinery to feature callers. The adapter
writer's private authority proofs and deterministic drift checks own aggregate
completeness; prose does not.

## Extension Procedures

### Add a Surface

1. Define the focused type-level declaration and feature marker types.
2. Add the production root to `RegisteredFrontendSurfaces`.
3. Add its typed adapter-family association and required homes/operation
   decisions.
4. Implement feature-owned scope/resource/domain adapters and `SurfaceImpl`.
5. Render mounts and fragments with typed runtime helpers; enforce route
   authorization.
6. Generate Haskell/TypeScript contracts and consume only curated/generated
   interfaces.
7. Add focused Hspec, compile-fail, frontend, and E2E coverage at the narrowest
   changed boundary.
8. Add a tombstone guardrail only when removing a legacy path that must not
   return.

### Add Or Change An Action/Intent

1. Declare exact fields and typed HTMX/form metadata in the owning Surface.
2. Register the operation's typed generation decision.
3. Regenerate the private module and curated facade.
4. Use the generated builder/metadata/parser at every production call site.
5. Characterize missing, malformed, repeated, optional/nullable/list, wrong
   operation, authorization, and domain validation behavior as applicable.

### Add A Live Fragment Or Resource

1. Declare typed scope/fragment/resource fields and scope authorization.
2. Select `DependsOn` or justified `ResyncOnly`; use typed mount targets.
3. Implement authorized plain-fragment rendering and feature-owned resource
   constructors/matchers.
4. Emit resources from the atomic mutation boundary and test actor/passive
   planning, containment, cross-scope authorization, and reconnect behavior.

### Add Interaction Or Browser DTO Vocabulary

1. Prefer an existing DSL alias or focused global capability.
2. Declare roles/refs/session/effects and explicit DTO reachability/direction.
3. Extend reflection, checked semantic IR, generation, and exact parser/encoder
   coverage together when the vocabulary is genuinely new.
4. Render generated roles from Haskell and keep TypeScript generic,
   mount-scoped, exhaustive, and effect-free until validation succeeds.

## Architecture Navigation

Use deterministic evidence instead of prose inventories:

```bash
bash ./bin/in-env architecture-facts
bash ./bin/in-env architecture-surface-request-closure --print-modules
printf '%s\n' '{"name":"generated-contracts","args":{"target":"roster"}}' \
  | bash ./bin/in-env architecture-query
printf '%s\n' '{"name":"realtime-flow","args":{"action":"UpdateRosterSlotAction"}}' \
  | bash ./bin/in-env architecture-query
```

The generated-contract query reports the checked reflection pipeline, selected
Surface semantics, generated browser contracts, and consumers. The closure check
owns exact request-facade module policy. Source and generated files remain the
authority for exact declarations, exports, and topology.

## Verification

Use focused checks during authoring, then the broader gates required by the
changed boundary:

```bash
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env frontend-surface-adapters-check
bash ./bin/in-env frontend-surface-compile-fail-check
# A named compile-fail fixture is the focused loop:
bash ./bin/in-env frontend-surface-compile-fail-check FrontendSurfaceWrongClosedScalarDomain
bash ./bin/in-env frontend-surface-guardrails
bash ./bin/in-env architecture-surface-request-closure --print-modules
bash ./bin/in-env typed-contract-authority-check
bash ./bin/in-env typecheck
bash ./bin/in-env frontend-check
bash ./bin/in-env hspec-test --match "FrontendSurface" --match "SurfaceDependency" --match "SurfaceGuard"
bash ./bin/in-env ./bin/doc-drift-check
```

Run feature-specific Hspec and Playwright when changing a concrete Surface,
controller, view, browser interaction, or live behavior. Documentation-only
changes do not regenerate contracts or alter these verification requirements.

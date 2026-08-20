# FrontendContract

`Application.Helper.FrontendContract` owns browser-visible contracts. Haskell
declarations are reflected into checked IR and generate
`frontend/ts/generated/contracts.ts`; server rendering, wire validation,
architecture facts, and TypeScript generation consume that same model.

## Interfaces And Ownership

- `Core` defines fields, presence, wire shapes, schemas, diagnostics, and typed
  HTMX values.
- `Naming` derives names for global and Surface declarations.
- `Registry` / `RegisteredFrontendContracts` own app-wide roots.
- `Surface.Registry` / `RegisteredFrontendSurfaces` own mounted feature
  contracts; `Surface.Contracts` binds reflection to the production registry.
- `IR` and `Surface.ContractIR` are the checked semantic models consumed by
  generators and runtime code.
- `Wire.Carrier` and focused `Wire.*` modules build/parse exact Haskell boundary
  values from registered declarations.
- `Surface/README.md` is the authoring and extension guide.

Global roots own app-wide browser capabilities and transport/DOM vocabulary.
Surface roots own feature scopes, resources, fragments, actions, intents,
mount-only state, and interaction metadata. Keep feature meaning in its focused
root; do not create aggregate registries or duplicate Surface metadata globally.

Each browser root declares reachability explicitly: server-only, type-only,
guard-only, inbound, outbound, or bidirectional. Generation emits only the
operations required by that direction. Plain server schemas, DOM values, and
Surface declarations remain Haskell-only unless a browser consumer is declared.

Field presence and recursive wire nullability are distinct. Optional fields may
be omitted; nullable fields must be present and may contain null. `WireUnknown`
is restricted to nested platform-owned values, not app-owned record fields.
Unknown inbound JSON is validated exactly before conversion to ergonomic carrier
ADTs; Haskell wire modules do not repeat field or case strings.

## Runtime Boundaries

Haskell owns routes, authorization, business meaning, workflow copy, server DOM,
and exact payload shapes. TypeScript consumes generated constants,
parsers/encoders, and minimal registries while keeping browser/platform mechanics
local. It must not infer business meaning from text, classes, positions, or
feature names.

Focused global contracts such as overlays, toggles, pickers, passkeys, ranges,
PWA install, and filters each own only their reusable browser boundary. Feature
request metadata remains in AppShell or Surface Actions/Intents. Native browser
objects, Bootstrap mechanics, transient classes, and initialization state do
not become generated app contracts.

`InteractionContract` owns generic interaction vocabulary. Feature-specific
source/dropzone/activation/session data is derived from Surface declarations
into the minimal interaction registry; live code separately consumes the
minimal fragment registry. Server-only actions, DTOs, topology, and mount state
do not leak into either registry.

## Generated Haskell Surface Adapters

Frontend-contract generation is a separate Nix output, not a production runtime
entry point. `.#frontend-contract-tools` owns the TypeScript contract renderer,
Surface Haskell-adapter renderer, and typed architecture emitter. Its checked
module inventory distinguishes 12 tooling-only modules from 81 shared canonical
authority modules; shared reflection remains in production only where runtime
builders, parsers, values, or metadata actually import it. The optimized server
closure must never reference the tooling output. Package-backed CI freshness
checks regenerate TypeScript, all managed Haskell adapters and private proofs,
and architecture contracts before accepting checked-in generated artifacts.

`AppShellAction` is the server-rendered lane for app-owned shell request initiators
that are not owned by a mounted `FrontendSurface`, including dialog/overlay
workflows targeting the generated shared dialog mount. The DSL owns
browser-visible HTMX metadata and submitted fields; Haskell still owns IHP
route/path construction through
`Application.Helper.FrontendContract.AppShell.Runtime`.
`Application.Helper.FrontendContract.AppShell.Request` derives nominal field
bundles, field names, reflected action metadata, route-field serialization, and
exact request parsers directly from `AppShellContract`. It converts only the
global DSL's type-level field view, then delegates all value construction,
lookup, diagnostics, and parsing to the existing Surface field evaluator;
AppShell has no second runtime registry or generator. Controllers and views must
select the same action marker, so wrong fields and cross-operation bundle reuse
fail compilation. Exact scalar parsing rejects repeated values, including
repeated empty optional values; repeated fields must declare `WireList`.

The guided Xero preparation period, staff-selection, managed-pay-item, and
submission forms use this nominal interface. The staff-selection operation no
longer carries a second `DecisionField` discriminator: the nominal action plus
its provider-owned employee selection is the complete request. Feedback submit
uses the same exact AppShell parser; optional browser diagnostics remain
best-effort fields in that nominal bundle. Their app-owned field names are not
handwritten in production views or reparsed with raw IHP parameter names.
Successful final dialog
workflow mutations should close/clear overlays and refresh business surfaces
through actor-local/passive invalidation rather than returning authoritative
business fragments OOB.


Private `.Generated.*` modules sit behind feature-owned curated facades. Feature
code uses those facades and marker-indexed builders/matchers; it does not scan
registries, construct raw names/JSON, import opaque internals, or call generic
Action/Intent metadata and parsers. All adapter lanes are generated atomically;
validation, formatting, and typechecking complete before publication or stale
file removal.

Generated TypeScript contract authorities come only from the Haskell DSL,
checked IR, or explicit support schemas consumed by the same renderer. Raw
TypeScript renderer strings may provide syntax templates, never independent
exported contract definitions.


`ClosedScalar value` registers an existing finite Haskell type as the canonical
request/browser schema, and `WireClosed value` carries that type without
collapsing it to `Text`. Persisted domains use their generated PostgreSQL enum
constructors directly; DSL-owned domains use their own `Bounded`/`Enum` ADT and
canonical `InputValue` projection. Reflection enumerates that exact type—there
is no registry scan or shadow ADT—and browser unions/guards/parsers are emitted
only for the declaration's explicit reachability. Production registrations include generated `RosterLayoutModeEnum`,
`RosterTemplateScaleEnum`, `VenueRoleEnum`, `StaffEmploymentBasisEnum`,
`FeedbackTypeEnum`, and `ShiftTypeColourKeyEnum`, plus app-owned profile section,
roster staff scope, leave section, and export-type authorities. Feature-local finite types live
with their Surface/domain module; the aggregate `ClosedScalars` module only
registers them. `RosterTemplateScaleEnum` drives the generated template-card DTO
union and guard, while `LeaveSectionValue` is browser-inbound because live mount
fragment keys carry it. Other request-only values remain server schemas.

Outer field presence remains separate from recursive wire nullability. An absent
`OptionalField` is omitted, a present optional nullable value can be explicit
`null`, every `NullableField` must be present, and list/optional/nullable source
containers remain recursive (`WireList WireUUID` maps to `[UUID]`, not `UUID`).
The same rule applies to `WireClosed`: optional, nullable, and nested-list
containers preserve the finite Haskell value type at every level.
Global `WireUnknown` is reserved for a nested platform-owned value whose
semantics are deliberately parsed by that platform adapter, currently WebAuthn
client extension results. It is not an escape hatch for app-owned record fields;
the containing app envelope remains exact.
`haskellWireSource` is the canonical checked-IR projection for deterministic
Haskell source generation. Exact marker-indexed IR validation lives in
`Application.Helper.FrontendContract.Wire.Json`; its old name-indexed public
entrypoint is intentionally absent. The migrated live-update carrier module is
`Application.Helper.FrontendContract.Wire.LiveUpdate`, which contains no wire
field, discriminator, or case literals.

Mechanical Haskell Surface adapters use the separate foundation under
`Application.Helper.FrontendContract.Surface.HaskellAdapter`. Nominal adapter
families are associated with existing Surface aliases once through
`AdapterFamilySurface`; resource, scope, and fragment homes are kind-indexed
uses of that association. Each Action or Intent inventory registration carries
its typed home and operation eligibility together, so no parallel request-home
list repeats ownership. None repeat fields, presence, or wires.
`HaskellAdapter.Core` is the single checked implementation
of Typeable metadata, source-type rendering, home/family/locality validation,
kind-indexed identity and collision checks, import aliases, deterministic module
layout, and generated-file bookkeeping. Resource identity is the checked shared
resource identity, scope identity is the runtime Surface identity, and fragment,
action, and intent identities are owning-Surface plus declaration identity, so
cross-kind marker/name reuse is valid.

Focused renderers select checked declarations and own only their function-level
source shapes. The resource renderer continues to emit byte-stable private
feature-adjacent `.Generated.Resource` modules. The Live renderer normalizes
scopes and fragments directly from checked `SurfaceIR`, preserves their kind
through home resolution, and combines only `LiveScope` and `LiveFragment` in
`.Generated.Live`; resources, actions, and intents cannot enter that lane.
Passive fragments are eligible from their closed `Live` option. The two
non-passive Admin parent-page keys remain typed, reason-bearing actor-only
exceptions. One `HaskellAdapter.Request` implementation normalizes Action and
Intent declarations through kind-indexed layouts and can emit only inventoried
field builders, render metadata, and exact request parsers. Inventory resolution
also supplies the validated adapter directly to rendering, avoiding a second
home/source projection. The compiled cross-kind fixture proves same-marker
Action/Intent output remains in separate private modules behind separate
facades.

The production registry assigns exactly one typed home to every checked Live
scope and eligible fragment. Empty, partial, extra, or duplicate production
homes fail generation. Seven private feature-adjacent `.Generated.Live` modules
now sit behind the seven curated `Surface.<Feature>.Live` facades. All mechanical
scope/fragment construction and matching is generated; handwritten facade code
is limited to domain-shaped matchers and active-scope orchestration. Curated
facades import and expose only operations with a production or test semantic
consumer.

Reachability deliberately distinguishes declaration-complete generated API from
curated runtime API. Within FrontendContract, `weeder.toml` roots only private
production `.Generated.Resource` and `.Generated.Live` modules: registry,
typed-home, all-kind generation, drift, and guardrail checks require every
declared constructor/matcher even when the executable graph consumes only one
side. The separate IHP-generated model Fetch statement category and exact
script entrypoints are framework/runtime roots, not FrontendContract
exceptions. Generated Action/Intent modules, curated facades, and all
handwritten modules remain subject to ordinary Weeder reachability; there is no
symbol allowlist or blanket FrontendContract suppression. The unregistered fixture continues to
prove zero-field and parameterized adapters, shared-module collision checks,
and public generic builder use.

Generated Resource and Live code calls only public marker-indexed builders and
matchers. Raw field data constructors stay hidden behind construction-only
functions. Every generated Action and Intent now uses a distinct nominal
operation token with `ActionFields operation`/`IntentFields operation` and one
local field-spec list. Builders, named presence witnesses, parsers, metadata,
lookup, and serialization contain no complete Surface. Generated term evidence
is rendered from checked IR and can be constructed only through a generated
request module's guarded runtime-internal edge. Temporary unpublished aggregate
proofs typecheck exact canonical Action and Intent set/owner/ordered-field
equality before managed publication. Every wrapper remains nominal, exposes no
split/re-indexing path, and reports unsupported source carriers with adapter
kind, compact owner, declaration, and field.
Production family associations remain feature-local, and the checked aggregate
resource registry assigns exactly one canonical home to every unique production
resource identity. Every private generated module has only its matching curated
facade consumer. The lightweight `HaskellAdapter.Association` seam carries
`AdapterFamilySurface` and compact owner projection into generated modules
without pulling registry/reflection mechanics from `HaskellAdapter.Family` and
`HaskellAdapter.Core` into focused feature compiles. Generated Action/Intent
modules import the focused `Surface.Request.Runtime` metadata seam rather than
the mount/live `Surface.Runtime`; their generated modules additionally import
`Surface.Request.Runtime.Internal` to construct checked evidence. Guardrails
permit only those generated edges plus the compatibility runtime and reject every
feature caller. Field construction remains in `Surface.Values`, exact parsing in
`Surface.Request`, and HTML rendering in `Surface.Runtime`.

`architecture-surface-request-closure` derives the focused request-facade
closures from source and rejects registered Surface catalogs, mount/live/wire
runtime, private proofs, and adapter-generator machinery in those closures. Its
policy file owns the exact expected module sets; do not duplicate generated
counts in prose.

`HaskellAdapter.Registry` is the single typed authority for Action/Intent homes
and operation eligibility, including explicit parser-only or excluded
operations. `frontend-operation-evidence-matrix.tsv` owns compile-failure
coverage and provenance. Generated modules remain private behind feature
facades, production callers cannot use generic parser/metadata calls, and raw
field constructors expose no bundle split or re-indexing path.

`generateSurfaceAdapterModules` is the mandatory all-kind composer used by the
write/drift workflow. It accumulates Resource, Live, Action, and Intent focused
lane diagnostics and validates duplicate physical paths before exposing the
complete managed set. Output for all four lanes is mandatory and complete; no
empty or partial publication state exists. The writer stages nothing when any
lane fails; the shell workflow formats and typechecks the entire temporary tree
before any managed stale deletion or write, so one failed or omitted lane cannot
discard another. Use `frontend-surface-adapters` to write
generated Haskell modules and `frontend-surface-adapters-check` to reject
missing, extra, unformatted, or stale output. Generation does not inspect
compiler syntax trees, parse source modules, or choose behavior from feature-name
text.

Generated TypeScript comes through
`Application.Helper.FrontendContract.Contracts`. Exported TypeScript contract
shapes must be rendered from Haskell DSL declarations, `FrontendContract.IR`, or
explicit Haskell support schemas consumed by the same renderer as ordinary
contracts. Raw TypeScript strings are allowed as renderer syntax templates and
for generated runtime data constants, but not as independent `export type` /
`export function` contract authorities. Helper implementations that normalize or
query generated data should live in handwritten `frontend/ts` runtime modules and
import generated types/data.

`FrontendSurface*` TypeScript names that remain in generated output are
runtime/mount metadata for server-rendered UI, not a parallel contract
authority. Reflection generates one exact per-surface mount type/guard and their
`FrontendSurfaceMountConfig` union; handwritten aggregate mount parsers and
compatibility aliases are forbidden. The live bundle consumes only
`FrontendSurfaceFragmentRegistry`; the interaction bundle consumes only
`FrontendSurfaceInteractionRegistry`. They remain separate and minimal; action
metadata and contained-surface topology stay server-only. Subscriptions, websocket invalidations, and actor details use the
generated `SurfaceScope` and semantic `SurfaceFragmentKey` contract types only.
Live-visible writes publish typed resources only through the atomic durable
mutation boundary. PostgreSQL versions/outbox are authoritative; process-local
state is limited to listener-fed subscription/socket routing and ordered-delivery
deduplication.
Shared server/browser DOM ids and semantic tokens come from reflected global or
Surface declarations, rather than copied string literals. Every fragment owns
one typed `MountTarget`; descriptor and view IDs are rendered through
`surfaceFragmentTargetId` from declaration-ordered typed fields. Server-only
`MountState` declarations are deliberately absent from browser output.

## Authority Reconciliation

`typed-contract-authority-check` is the blocking zero-bypass source gate. It
rejects generic production Surface Action/Intent parser or metadata calls,
handwritten migrated operation field names, finite fields regressed to
`WireText`, retired decision/discriminator envelopes, rendered-enum branching,
and any non-empty Weeder baseline. Two open shapes are explicitly classified:
pay-rate selection is a server-validated tagged Award/Xero UUID or roster-only
reference, and Xero employee selection carries provider-owned ids plus the
not-applicable sentinel. Neither is falsely represented as a finite scalar;
both retain nominal generated field-name ownership.

The historical reporting audit uses structural source checks for contract-bound
vocabulary rather than broad word-based regexes; generated adapter drift,
publication, compile-failure, and CSS ownership checks protect the same authority
boundary. `frontend-contract-warnings` discovers the exact reflected registry
closure, precompiles generated/framework dependencies, then applies curated
warning errors only to reachable app-owned sources. Generated IHP source warnings
are not an application authority failure.

Verify current authority and generated ownership with
`typed-contract-authority-check`, `frontend-check`, `weeder-check`, and
`verify-full`; source-derived checks own current file, line, and closure counts.
#151 is separately approved live-data schema-retirement work, not a
FrontendContract compatibility exception. The historical audit and closeout
evidence are archived at `docs/archive/frontend-contract-authority-hardening.md`.

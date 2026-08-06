# FrontendContract

`Application.Helper.FrontendContract` is the source of truth for browser-visible
contracts. Contracts are declared in the project DSL, evaluated through explicit
typeclass reflection, checked as contract IR, and rendered to
`frontend/ts/generated/contracts.ts`. Global roots come from
`RegisteredFrontendContracts`; Surface roots come from
`RegisteredFrontendSurfaces` through the single checked reflected
`SurfaceContractIR`. The generic `Surface.Reflect` evaluator stays independent
of the production registry; `Surface.Contracts` binds the two for aggregate
runtime/generation consumers. The unified `FrontendContractIR` embeds those
checked `SurfaceIR` values directly. `Application.Helper.FrontendContract.Core` owns the
shared field, wire, schema, diagnostic, and HTMX model, while
`Application.Helper.FrontendContract.Naming` owns naming for both roots.
Generation, server runtime metadata, validation, and semantic Surface
architecture facts consume that model directly; there is no shallow Surface
copy or conversion layer. Test-only Surface fixtures are reflected explicitly
from `Test/` and never enter `RegisteredFrontendSurfaces` or generated production
browser output. Haskell feature code consumes Surface declarations
through marker-indexed accessors and exact `SurfaceFields` in
`Surface.Values`, rather than registry scans or phantom JSON. Those APIs keep
the declared field list as their inference context and expose compact,
marker-named ownership and field-shape diagnostics; the diagnostic contract is
documented in `Surface/README.md`. Live scopes and
fragment keys use the declaration-complete constructors and typed matchers in
`Surface.Live`; raw transport constructors remain internal and feature-owned
identity values live in the corresponding `Surface.<Feature>.Live` module.
Surface resources follow the same shape: `Surface.Resource` owns the opaque
marker-indexed constructor/matcher seam, and concrete values plus domain
matchers live in `Surface.<Feature>.Resource`. No feature-facing free-name/JSON
resource constructor exists. Common Surface
HTMX selectors, triggers, swaps, and sync recipes are typed and render their own
deterministic punctuation; raw syntax requires a non-empty recorded reason.

Every browser root declares explicit reachability: unreachable/server-only,
type-only, guard-only, inbound (type/guard/parser), outbound (type/encoder), or
bidirectional. Exceptional aggregate projections are likewise explicit checked
IR declarations such as `ProjectInteractionDom`; the generator never selects
behavior from a reflected root or Surface name. The TypeScript renderer emits
only the operations justified by that direction. `ServerSchema`, `ServerEvent`,
`ServerDomId`, and `ServerDomAttr` keep Haskell runtime vocabulary in the
reflected IR without creating browser exports. A Haskell-only schema or Surface
declaration remains
available to validation, rendering, and architecture facts without
automatically becoming browser output. Wire primitive aliases are likewise
emitted only when a reachable browser shape uses them.

Roots are split by meaning:

- **Global**: app-wide browser/runtime vocabulary such as DOM ids, event names,
  closed enums, UI-region data, generic interaction runtime shapes, focused
  toggle/overlay/passkey capabilities, live-update wire schemas, and app-shell request
  contracts.
- **Surface**: mounted feature UI semantics: scopes, fragments, actions,
  intents, server-side mount state, resources, and interaction metadata.

`OverlayContract` is the focused global workflow-dialog/toast capability. It
owns the two lane mount ids, generated dialog/backdrop/close/submit and
toast/close roles, the semantic dialog-dismissed event, dialog auto-submit
state, and exact dialog-submit/toast configuration schemas.
`Application.Helper.FrontendContract.Overlay.Runtime`
serializes those configs from declaration-indexed fields for the shared view
helpers. The TypeScript adapters parse only the generated exact configs, emit
the generated dismissal event before every close-control, backdrop, or Escape
removal, and keep transient initialization/original-markup state outside the DOM. Bootstrap
classes/events and ARIA/native state remain inside the focused adapters rather
than becoming app DOM primitives. Overlay request routes, HTMX methods, targets,
and fields remain owned by generated AppShell or Surface Action helpers.

`ToggleContract` is the focused global checkbox-style capability. It owns closed
presentation and submission states, explicit value-or-omitted targets, the exact
browser configuration parser, and shared DOM role attributes. Its Haskell
runtime accepts complete marker-indexed Surface Action bundles for scalar and
list fields, preserving a compile-time link from feature declarations to the
form-local browser transport. The full authoring/runtime rules live in
`Surface/README.md`.

`TimePickerContract` is the focused global quarter-hour picker capability. It
owns the modal id, picker-internal field/value/trigger/label/step/options/option/
clear roles, and exact field configuration and option schemas. The Haskell
runtime serializes declaration-indexed range, step, empty-state copy, value, and
label fields; the generic TypeScript adapter parses those exact records and only
rearranges validated server-rendered option nodes. Malformed elements are
reported and skipped without replacing their server HTML. Toggle transport and
break-field activation remain exclusively owned by `ToggleContract`.

`OrderedRangeContract` is the focused global two-endpoint range capability. It
owns root/config/state/start/end/availability roles, exact allowed range, step,
default, label inventory and initial-state records, generated CSS position
properties, and the closed `clamp-other-endpoint` crossing policy. Its Haskell
runtime serializes declaration-indexed records and rejects inconsistent semantic
inventories. The generic TypeScript adapter validates the complete local native
checkbox/range/output subtree before mutation, keeps initialized state in a
`WeakMap`, and supplies no fallback values or labels. Toggle remains the owner of
availability submission transport, while controller validation remains the
business authority for submitted endpoints.

`PwaInstallContract` is the focused global installation-page capability. It owns
generated page, button, result, result-state, and installed-status roles plus the
closed accepted/dismissed/failed result state. The Haskell runtime renders every
workflow message and associates it with that state. The TypeScript adapter keeps
`beforeinstallprompt`, `appinstalled`, prompt objects, and platform detection
local, and changes only native `hidden` state to expose server-rendered copy.
Those browser-platform objects are not wire schemas.

`PasskeyContract` is the focused global passkey workflow capability. It owns
login, registration, setup-prompt, action-button, device-name, status, recovery,
and dismissal roles plus one exact tagged flow configuration. It also declares
the exact registration/authentication begin options, serialized credential
requests, tagged finish outcomes, and tagged structured errors. Haskell supplies
begin/finish routes, an optional success redirect, a mount-local status key, the
opaque prompt user key, closed first-passkey/additional-device mode, and all
workflow/status/recovery copy through `FrontendContract.Passkey.Runtime` and
`Application.Helper.View.Passkey`. `Wire.Passkey` builds and parses those JSON
boundaries through schema-indexed carriers; controllers do not call the
WebAuthn library's JSON option encoder or construct response objects by field
name. The TypeScript adapter parses each inbound server envelope before a
credential API or redirect, uses generated request encoders, validates the
complete local subtree before installing listeners, reports structured
diagnostics, and leaves malformed server HTML untouched. Native WebAuthn
credential/response objects, extension-result semantics, navigator calls,
base64url conversion, and local-storage UX hints remain in the focused
TypeScript adapter and are not recreated as generated platform schemas. Prompt
dismissal bears both the semantic generated passkey dismissal role and the
generated overlay close role; the overlay adapter alone owns removal and body
locking.

`XeroCandidateFilterContract` is the focused global pay-item candidate-filter
capability. It owns generated root, search, candidate, and empty-state roles plus
an exact candidate config carrying one search projection. The Haskell runtime
keeps normalized search projections opaque and the
Xero view explicitly selects the earnings-rate name and account code that
contribute. The TypeScript adapter scopes itself to one generated root, performs
only exact config parsing, structured boundary diagnostics, generic query
normalization/fuzzy matching, and native `hidden` changes. Server-rendered
checkbox identity, copy, validation, and import mutations
remain Xero-owned.

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

The guided Xero preparation period, staff-decision, managed-pay-item, and
submission forms use this nominal interface. Their app-owned field names are not
handwritten in production views or reparsed with raw IHP parameter names.
Successful final dialog
workflow mutations should close/clear overlays and refresh business surfaces
through actor-local/passive invalidation rather than returning authoritative
business fragments OOB.

`InteractionContract` is intentionally generic runtime vocabulary: activation
triggers, field presence, conflict/effect shapes, DOM attrs, values, and pointer
field names. Browser code consumes those names through the generated
`InteractionDom` object. Interaction effects lower to closed semantic IR
carrying typed lifecycle, layer, source, option, and CSS-class choices; browser
spellings are derived from typed markers and never recovered from effect text.
Feature-specific interaction runtime data is derived from registered
`FrontendSurface` declarations into the minimal
`FrontendSurfaceInteractionRegistry`; action metadata, DTO aliases, full static
schemas, and other server-only Surface data are not emitted. Do not add
compatibility shim aliases that resurrect global `Interaction*` roster enums.

Haskell wire code must not re-declare browser shapes. Ergonomic carrier ADTs use
the declaration-indexed builders and exact parsers in
`Application.Helper.FrontendContract.Wire.Carrier`. `recordValue`, `eventValue`,
and `taggedUnionValue` select their complete field/case shape from
`RegisteredFrontendContracts`; their matching parsers validate the unknown
`Aeson.Value` against reflected IR, then expose declaration-ordered typed values
directly to the carrier constructor. No validated value is encoded and decoded
again, and ordinary feature code does not import parser classes or field
constructors.

`ClosedScalar value` registers an existing finite Haskell type as the canonical
request/browser schema, and `WireClosed value` carries that type without
collapsing it to `Text`. Persisted domains use their generated PostgreSQL enum
constructors directly; DSL-owned domains use their own `Bounded`/`Enum` ADT and
canonical `InputValue` projection. Reflection enumerates that exact type—there
is no registry scan or shadow ADT—and browser unions/guards/parsers are emitted
only for the declaration's explicit reachability. Production registrations
currently include server-carried `RosterLayoutModeEnum` and browser-inbound
`RosterTemplateScaleEnum`; the latter drives the generated template-card DTO
union and guard consumed by the roster TypeScript runtime.

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
matchers. Raw `SurfaceFields` data constructors stay hidden behind the
construction-only `noSurfaceFields` and `(&:)` functions. Generated production
Action/Intent builders construct nominal `SurfaceActionFields surface action`
or `SurfaceIntentFields surface intent` directly from the declared first field
and exact tail (or the explicit zero-field constructor). The request parser
keeps its recursive parsed-field view private and calls that same public nominal
construction seam; no parser-only rebind operation is exported. Generated
metadata and structured parser interfaces carry the exact wrapper, so
operations with equal normalized field lists remain distinct. Read-only marker
lookup and serialization stay shared through `SurfaceFieldBundle`, which
exposes no unwrap operation. Unsupported source carriers fail with adapter kind,
owning Surface, declaration, and field in the diagnostic.
Production family associations remain feature-local, and the checked aggregate
resource registry assigns exactly one canonical home to every unique production
resource identity. Every private generated module has only its matching curated
facade consumer. The lightweight `HaskellAdapter.Association` seam carries
`AdapterFamilySurface` into generated modules without pulling
registry/reflection mechanics from `HaskellAdapter.Family` and
`HaskellAdapter.Core` into focused feature compiles. Generated Action/Intent
modules also import the focused `Surface.Request.Runtime` metadata seam rather
than the mount/live `Surface.Runtime`. The focused seam owns opaque request
metadata values and marker-indexed constructors; field construction remains in
`Surface.Values`, exact parsing remains in `Surface.Request`, and HTML rendering
remains in `Surface.Runtime`. The broad runtime consumes read-only metadata
selectors without re-exporting the focused interface.

The exact source-derived closure contract is checked by
`architecture-surface-request-closure`: Profile Action retains 20
`Application.*` modules and Roster Intent retains 21, with no unrelated Surface
catalog, mount/live/wire runtime, or Haskell adapter generator implementation.
The compiler-observed baseline, candidate sets, deltas, and retained-dependency
classification are recorded in `Surface/README.md`.

The production operation inventory covers all 62 actions and six intents. It
marks 57 actions as adapter-eligible, with builders/render metadata for 56 and
exact parsers for 42. The hidden roster-week-start compatibility mutation is
parser-only with typed builder/metadata exclusions; five same-named
intent-backed actions are excluded from adapter eligibility, while 15 parser
operations retain typed reasons. Exactly one inventory registration owns the
home and operation decisions for every Action and Intent. Seven private
feature-adjacent `.Generated.Action` modules sit behind seven curated
`Surface.<Feature>.Action` facades, while the six Roster intents share one
private `Surface.Roster.Generated.Intent` module behind `Surface.Roster.Intent`.
Production callers contain no generic Action or Intent parser/metadata calls.
Raw `SurfaceFields` constructors are hidden behind construction-only builders.
Nominal construction accepts only the declared first field plus its exact typed
tail (or an explicit zero-field constructor), so the compiler exposes no raw
bundle split/re-indexing path. Compile-failure coverage rejects
cross-operation Action and Intent reuse for identical field shapes. The #191 and #187 independent request-adapter checkpoints pin production
bundles, literal DOM-owned metadata, structured parsing, and diagnostics across
the migrated Profile/Staff Actions and Roster Intents. Nullable and nested-list
request shapes remain owned by the compiled #185 fixture rather than invented
production declarations.

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
Shared server/browser DOM ids and semantic tokens come from reflected global or
Surface declarations, rather than copied string literals. Every fragment owns
one typed `MountTarget`; descriptor and view IDs are rendered through
`surfaceFragmentTargetId` from declaration-ordered typed fields. Server-only
`MountState` declarations are deliberately absent from browser output.

## Authority Reconciliation

The zero-legacy authority audit uses structural source checks for
contract-bound vocabulary rather than broad word-based regexes; generated
adapter drift, publication, compile-failure, and CSS ownership checks protect
the same authority boundary. `frontend-contract-warnings` discovers the exact
reflected registry closure, precompiles generated/framework dependencies, then
applies curated warning errors only to the reachable app-owned FrontendContract
sources. Generated IHP source warnings are not an application authority failure.
Verify it with `verify-full`, `lint`, and `format`.
#151 is separately approved live-data schema-retirement work, not a
FrontendContract compatibility exception. The historical audit and closeout
evidence are archived at `docs/archive/frontend-contract-authority-hardening.md`.

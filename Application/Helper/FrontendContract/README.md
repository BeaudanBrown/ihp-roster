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

Mechanical Resource, Live, Action, and Intent adapters are derived from checked
Surface declarations. `HaskellAdapter.Core` owns type/source rendering, typed
home validation, collision checks, deterministic module layout, and managed-file
bookkeeping. Focused renderers own only kind-specific source shapes.

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

## Extension And Verification

Add vocabulary to the existing DSL/reflection/checked-IR path, register the root
at its owning global or Surface seam, generate artifacts, and update the real
runtime consumer. Do not add a second evaluator, registry, compatibility alias,
name-dispatched generator, or handwritten browser contract.

```bash
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env frontend-surface-adapters-check
bash ./bin/in-env frontend-surface-compile-fail-check
bash ./bin/in-env frontend-surface-guardrails
bash ./bin/in-env frontend-check
bash ./bin/in-env hspec-test --match "FrontendContract" --match "FrontendSurface"
printf '%s\n' '{"name":"generated-contracts","args":{"target":"all"}}' \
  | bash ./bin/in-env architecture-query
```

Use `bash ./bin/in-env architecture-surface-request-closure --print-modules` for
generated request facade closure and `verify-full` for the complete repository
gate.

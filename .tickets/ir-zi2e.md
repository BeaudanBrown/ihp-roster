---
id: ir-zi2e
status: closed
deps: []
links: []
created: 2026-07-08T07:20:33Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jvjj
tags: [frontend-contracts, typescript, audit]
---
# Audit hardcoded TypeScript generation blocks

Inventory hardcoded TypeScript declarations and helper functions emitted by Application.Helper.FrontendContract.TypeScript.

## Design

Classify each block as derived schema rendering, contract-looking handwritten scaffold, runtime helper implementation, primitive wire mapping, or manifest data renderer. Identify its Haskell source of truth or target destination.

## Acceptance Criteria

Ticket note records the inventory, risk, owner/source-of-truth for each class, and proposed migration order; no implementation beyond planning unless it is a tiny clarifying test.


## Notes

**2026-07-08T07:21:06Z**

Initial audit of Application.Helper.FrontendContract.TypeScript hardcoded TypeScript generation:

1. Header built-ins: FrontendContractUuid, FrontendContractDay, FrontendSurfaceUUID, FrontendSurfaceDay, isRecord, and FrontendSurfaceInteractionDom are emitted as raw strings. UUID/Day names are used by renderWire and tests, so they should be Haskell value-level wire primitive names, not handwritten header text. FrontendSurfaceUUID/Day appear to be adapter/brand aliases and should either be removed or declared from an explicit Haskell source. FrontendSurfaceInteractionDom is derived from surface interaction DOM attrs in spirit but currently bypasses the Global DomAttr renderer.

2. Generic schema renderer output is mostly acceptable: renderSchema/renderRecordAlias/renderCodec/renderWire render TypeScript syntax from SchemaIR/FieldIR/WireIR. It still uses string templates, but those templates are renderer mechanics rather than independent contract authority. Guardrails should allow these generic emitters.

3. Global convenience groups: InteractionDom and InteractionStaticSchemaRegistry are bespoke generated groups. InteractionDom is a convenience object derived from GlobalDomAttr/DomValue/FieldName primitives, acceptable if kept as a derived view. InteractionStaticSchemaRegistry type/codec is currently handwritten around derived surface data; it should become an explicit built-in schema/IR construct or be moved to runtime helper code with only data generated.

4. Surface aliases and manifests: per-surface name/fragment/action/intent aliases and manifest constants are derived from SurfaceIR, but manifest support types (HtmxActionOptions, FrontendSurfaceActionManifest, AppShellActionManifest) are hardcoded. These should be promoted to Haskell-declared schema/IR records because they are browser-visible contract types.

5. FrontendSurface live/mount adapters: FrontendSurfaceScope, FrontendSurfaceLiveFragment, FrontendSurfaceSurfaceFragmentProtection, FrontendSurfaceLiveWireFragment, FrontendSurfaceLiveSubscription, FrontendSurfaceMountedFragmentConfig, and FrontendSurfaceMountConfig are hand-authored TS shapes and validators. They overlap Haskell carriers in Surface.Runtime and LiveUpdateContract/Wire.LiveUpdate. This is the highest drift risk and should be derived from those Haskell declarations or moved into frontend runtime code if they are only parser adapters.

6. Registry helper functions: FrontendSurfaceRegistry, containment topology, isFrontendSurfaceName, source/dropzone/activation ref helpers are mixed. Registry data and FrontendSurfaceName union are derived from SurfaceIR; helper function bodies are runtime code and can likely move to handwritten frontend modules importing generated registry data/types.

7. Rendered static interaction data: renderStaticSchema/renderSessionEffects currently hardcode some effect details such as clone-shadow/dropzone-highlight class names and the roster drag description. These are not merely TypeScript string issues; they are Haskell-side derived data gaps. They should eventually be represented in Surface interaction IR/options if they remain browser-visible contract data.

Suggested migration order: wire primitive aliases first; manifest/HTMX support schemas next; mount/live adapter schemas next; move non-contract helper implementations out of generated output; then add guardrails. Keep generic renderer templates, but remove independent exported type/function strings whose names/shapes are not produced from Haskell contract declarations.

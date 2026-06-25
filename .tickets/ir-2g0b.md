---
id: ir-2g0b
status: closed
deps: [ir-k3q0, ir-bfj9]
links: []
created: 2026-06-25T11:57:30Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-vpmd
tags: [agent-loop, frontend, contracts, haskell, live-surfaces, interaction]
---
# Generate registered surface manifest and omission guards

Make registered live surfaces/fragments/interactions visible to frontend contract generation and fail when a server-emittable concept lacks schema coverage.

## Design

Extend Web.LiveSurfaceRegistry or add a sibling static frontend registry that lists registered surface schemas independently of request-specific runtime values. Generate a manifest of known surface families, wire scopes/fragments, default fragment sets where static, and interaction schemas per surface. Add Haskell guard tests that a registered live surface cannot be omitted from frontend contract generation.

## Acceptance Criteria

Generated contracts include a surface/fragment/interaction manifest derived from the registered Haskell schemas; adding a registered surface without frontend schema fails a focused guard test or contract drift check; no runtime URLs/ids are statically baked into the manifest; focused LiveSurface tests pass.


## Notes

**2026-06-25T13:31:35Z**

Generated a registered live-surface manifest from Web.LiveSurfaceRegistry. Added RegisteredLiveSurfaceManifest/registeredLiveSurfaceManifest as the static registry for surface family, scope kinds, fragment kinds, and interaction schema linkage. Added Application.Helper.Frontend.SurfaceManifestSchema to emit LiveSurfaceFamily, RegisteredLiveSurfaceScopeKind, RegisteredLiveSurfaceFragmentKind, and LiveSurfaceManifest into generated contracts.ts without runtime URLs/ids. Updated frontend tests to consume LiveSurfaceManifest and assert no runtime URLs are baked in. Added Hspec guard that every registered surface family appears in generated frontend contracts, plus guard allowances for generated frontend schema modules. Verified frontend-check, frontend-contracts-check, typecheck, focused FrontendContracts/LiveSurface Hspec, and LSP diagnostics.

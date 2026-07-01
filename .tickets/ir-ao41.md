---
id: ir-ao41
status: open
deps: []
links: [ir-6kzl]
created: 2026-07-01T02:44:57Z
type: epic
priority: 2
assignee: beaudan
parent: ir-jsyd
tags: [agent-loop, frontend, interaction, typescript, haskell, contracts]
---
# Generic pointer session effects and previews

Add a generic pointer-session effect architecture so typed interaction surfaces can declare reusable preview and highlight behavior for pointer interactions without feature-specific JavaScript. The first proof covers clone-shadow session-global previews and dropzone-highlight contextual effects for the existing roster day-row drag/drop path.

## Design

Session effects are Haskell-owned interaction metadata, not frontend-only configuration. Extend the interaction static schema and the browser DTO seam in Application.Helper.Frontend.Dto.Interaction so generated contracts expose effect DTO types plus InteractionStaticSchemas values. Runtime TypeScript resolves effects from generated InteractionStaticSchemas using the mounted surface family and session kind, then runs generic effect handlers through a two-tier lifecycle: session-global effects activate after the movement threshold and clean up at session end; contextual target effects activate/update/cleanup as the pointer moves across hit-tested targets. The initial effect union is intentionally small: clone-shadow and dropzone-highlight. Clone-shadow clones the pointer-session marker into a declared disposable layer, sanitizes interactive/server-owned attributes, uses a configured CSS class, and preserves the original pointer grab offset. Dropzone-highlight temporarily applies/removes a configured class on the active dropzone and must clean previous targets on target change. No runtime branch may hardcode roster session/layer names; roster only declares generic effects in its Haskell interaction schema.

## Acceptance Criteria

Interaction docs describe session-global and contextual effect lifecycles and the DTO/generation path. Haskell interaction types and Application.Helper.Frontend.Dto.Interaction expose generated effect contracts with type/is/parse/encode helpers. The pointer-session runtime resolves effect config from generated InteractionStaticSchemas and runs generic handlers without roster-specific branches. Roster drag declares clone-shadow and dropzone-highlight through Haskell static schema. Drag shadow preserves grab offset, lives in a declared disposable layer, has pointer-events disabled, and cleans up on commit/cancel/Escape/pointercancel/HTMX cleanup. Dropzone highlight changes and cleans up as the pointer target changes. Existing move-roster-shift-to-slot submission semantics remain unchanged. Focused frontend unit/DOM tests, generated contract checks, Hspec interaction/frontend-contract tests, and focused E2E coverage where browser behavior requires it pass.


---
id: ir-fq28
status: open
deps: [ir-4uuy]
links: []
created: 2026-06-25T01:05:44Z
type: task
priority: 2
assignee: beaudan
parent: ir-jsyd
tags: [agent-loop, haskell, frontend, htmx, interaction, live-fragments]
---
# Add typed interaction capabilities to live surfaces

Define Haskell types that attach optional interaction capabilities to existing typed live surfaces while preserving empty/null interaction definitions for current surfaces.

## Design

Build on `Application.Helper.LiveSurface.TypedLiveSurfaceDefinition`. Do not create a parallel free-text interaction system. Add a typed interaction-capability layer, likely as a sibling/wrapper definition, that can reference a `TypedLiveSurfaceDefinition surface scope fragment` and add:

- concrete surface mount keys for duplicate/movable instances;
- server-layer and disposable-layer declarations;
- typed disposable layer enums;
- typed session kinds where needed by browser policy;
- typed intent enums;
- string-only intent field schemas for the form boundary;
- typed HTMX intent form contracts: trigger, route/action, method, target fragment or mount-local target, swap behavior, hidden fields, and optional sync/disable metadata;
- live-fragment conflict policy between active disposable sessions and typed fragments.

Existing live surfaces should be representable with empty interaction capabilities. Prefer explicit empty types or empty capability values over unsafe `Text` placeholders. Keep feature-local closed ADTs for layers/intents the same way feature-local fragment enums are used today.

The types should support surface portability: a surface family + scope + mount key can derive distinct DOM ids, form ids, and targets so the same surface can be mounted on different pages or more than once on one page.

## Acceptance Criteria

- A Haskell interaction-capability model exists and can wrap or sit beside existing `TypedLiveSurfaceDefinition` values.
- Current typed live surfaces can declare empty interaction capabilities and compile without behavior changes.
- Types distinguish surface family, scope, concrete mount, live fragments, server layers, disposable layers, session kinds, intents, field schemas, HTMX form contracts, and conflict policies.
- The model keeps persistence routes/targets/swaps server-owned and does not require TypeScript to construct URLs.
- There is a clear aggregation point for later frontend contract generation.
- Docs or comments explain how feature-local surfaces opt in incrementally.
- `bash ./bin/in-env typecheck` passes.


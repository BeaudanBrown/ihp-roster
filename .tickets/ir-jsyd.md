---
id: ir-jsyd
status: open
deps: []
links: [ir-vpmd, ir-o5qk, ir-ewlr, ir-cfcr, ir-osr3, ir-21jr, ir-f2p4, ir-jooi, ir-zqp3, ir-p008, ir-62zx, ir-qbm4]
created: 2026-06-16T13:44:46Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, frontend, htmx, interaction, live-fragments, typescript]
---
# Typed disposable interaction surfaces and intent bridge

Extend typed live surfaces with optional typed interaction capabilities so Haskell-generated contracts/render helpers define valid surface mounts, server layers, disposable layers, intent forms, HTMX submission metadata, and live-fragment conflict policy; TypeScript consumes generated contracts through generic runtimes.

## Design

Build on the existing strict typed live-surface architecture rather than creating a separate string-based interaction system. A surface family and scope remain Haskell-owned. A concrete surface mount adds a mount key so the same scope can be moved across pages or mounted more than once without DOM id, HTMX target, or form collisions.

Interaction capability is optional. Existing live surfaces start with empty disposable-layer, intent, field-schema, and conflict-policy definitions. Feature modules can then opt in by adding closed Haskell types for disposable layers and intents, Haskell intent field schemas, generated HTMX form contracts, and live-fragment conflict policies. TypeScript is generated from those Haskell definitions where possible and must not invent canonical surface, fragment, layer, or intent strings.

The canonical hierarchy is: surface family -> surface scope -> concrete mount -> server layer/live fragments plus disposable layers/sessions plus intent forms. Server-rendered HTML remains authoritative. Disposable UI is temporary client-owned DOM inside Haskell-declared disposable layers and must be safe to clear. Generic TypeScript runtimes may manage sessions, previews, ghosts, menus, selection rectangles, and similar disposable UI, but cannot mutate business DOM or construct mutation URLs.

Committed intents submit through Haskell-rendered HTMX forms. The generic bridge fills generated hidden inputs and dispatches generated custom HTMX triggers; routes, verbs, targets, swaps, and validation remain server-owned. Use standard HTMX primitives first: generated forms, custom event `hx-trigger`, lifecycle events, `hx-sync`/`hx-disabled-elt` where useful, and OOB swaps. Do not start with HTMX extensions/custom elements; revisit only after stable repeated lifecycle behavior justifies it.

Live updates and disposable sessions share the same typed surface origin. Live fragments may update behind an active disposable session when the fragment cannot invalidate active anchors/targets/forms. Conflicting swaps should apply, defer, or cancel according to Haskell-owned policy. Actor HTMX responses for the committed intent win and clear disposable UI.

See `docs/workstreams/typed-interaction-surfaces.md` for the planning vocabulary, hierarchy, non-goals, and implementation order.

## Acceptance Criteria

- A documented typed interaction architecture exists and is linked from local frontend/static/live-surface docs.
- Existing typed live surfaces can declare empty interaction capabilities without behavior changes.
- Haskell types model surface families/scopes/mounts, live fragments, disposable layers, intents, intent field schemas, HTMX form contracts, and conflict policies.
- TypeScript contracts for interaction browser boundaries are generated from Haskell and checked for drift.
- Haskell helpers render interaction surface mounts, server layers, disposable layers, typed markers, and HTMX intent forms; feature views do not handwrite raw interaction attrs/forms.
- A generic TypeScript intent bus/form bridge submits committed intents through generated forms without JS-built URLs or business DOM mutation.
- At least one low-risk prototype proves click/keyboard/touch activation, typed fields, server-rendered response, and mount portability.
- Follow-up pointer/touch, live coordination, timeline drop, and resize tickets use the same typed model.


## Notes

**2026-06-25T01:39:18Z**

Plan update: added ir-libm to fold interaction capability into TypedLiveSurfaceDefinition before render helpers, so the ir-fq28 wrapper remains a bridge rather than the long-term surface origin.

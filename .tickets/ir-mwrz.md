---
id: ir-mwrz
status: open
deps: [ir-w50d, ir-mlle, ir-ptnv]
links: []
created: 2026-06-16T13:46:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jsyd
tags: [agent-loop, frontend, htmx, mobile, interaction, timeline]
---
# Prototype timeline drop intent

Build a prototype timeline/drop surface that uses typed server-declared slots, lanes, disposable layers, and HTMX intent forms to submit a generic drop intent.

## Design

Use the typed interaction architecture rather than feature-specific persistence JavaScript. The chosen timeline surface should declare typed disposable layers, typed item/container/slot markers, and a typed drop intent field schema. Haskell helpers render the mount, server layer, disposable layer, drag handles/targets, and intent form. TypeScript pointer primitives create a ghost/preview in the disposable layer; the real item remains in server-owned DOM until the server response.

On commit, submit opaque string tokens such as item id, from-container id, to-container id, and slot id through the generated HTMX intent form. The server maps tokens to domain values and validates permissions, venue/scope, overlaps, availability, and final state. Validation failures should clear previews and show server-rendered feedback.

## Acceptance Criteria

- A prototype timeline item can be dragged with mouse and touch/handle interaction to a declared lane/slot.
- Drag preview is disposable and server DOM remains unchanged until the HTMX response.
- Commit submits only typed opaque tokens through the generated form; no JS-built URL or business mutation exists.
- Server validates the intent and returns authoritative refreshed fragment(s).
- Validation failure clears disposable UI and renders server feedback.
- Live-update/session coordination handles conflicts without stale ghosts.
- Focused frontend, Hspec, and E2E coverage pass for the prototype path.


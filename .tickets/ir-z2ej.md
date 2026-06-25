---
id: ir-z2ej
status: open
deps: [ir-mwrz]
links: []
created: 2026-06-16T13:46:10Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jsyd
tags: [agent-loop, frontend, htmx, mobile, interaction, timeline]
---
# Prototype timeline edge resize intent

Build a prototype for changing a timeline block duration by dragging a typed start/end resize handle while keeping server DOM authoritative.

## Design

Build on the timeline drop prototype and reuse the typed interaction model. Resize handles should be Haskell-rendered from typed helper contracts. Pointer resize sessions draw a translucent preview in a declared disposable layer and snap to server-declared slots/edges. The real block remains unchanged until the server response.

On commit, submit opaque tokens such as item id, edge, and slot id through a generated HTMX intent form. The server validates permissions, scope, min duration, overlaps, and final timestamps. Errors, passive live conflicts, and actor responses must clear disposable UI and leave authoritative DOM consistent.

## Acceptance Criteria

- A timeline block can be resized from start or end with mouse and touch/handle interactions.
- Preview is disposable and server DOM remains unchanged until response.
- Commit submits typed opaque tokens only through the generated form.
- Server response replaces authoritative fragment(s); validation errors render server feedback and clear previews.
- Live update conflicts and HTMX errors cancel/refresh sessions cleanly.
- Focused frontend, Hspec, and E2E coverage pass for the prototype path.


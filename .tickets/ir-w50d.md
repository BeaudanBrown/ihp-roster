---
id: ir-w50d
status: open
deps: [ir-4uuy]
links: []
created: 2026-06-16T13:45:39Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jsyd
tags: [agent-loop, haskell, frontend, htmx, interaction]
---
# Add declarative surface and interaction-layer helpers

Provide reusable IHP/HSX helpers or conventions for rendering interaction surfaces, server layers, JS-owned interaction layers, items, targets, slots, and intent forms consistently.

## Design

Prefer small view helpers over hand-written attribute sets where repeated. Helpers should render data-bepis-surface, data-bepis-server-layer, data-bepis-interaction-layer, data-bepis-item-id, data-bepis-dropzone-id, data-bepis-slot-id, resize handle markers, and intent forms with hidden inputs. Keep tokens opaque/stable where possible so the server maps slot/container ids to domain values.

## Acceptance Criteria

At least one shared helper/convention renders the standard surface shell and intent form; examples in docs match the helper output; generated markup keeps HTMX method/URL/target/swap in server-rendered HTML.


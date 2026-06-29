---
id: ir-vgwk
status: open
deps: [ir-fp76]
links: []
created: 2026-06-29T13:12:15Z
type: feature
priority: 2
assignee: beaudan
parent: ir-21jr
tags: [agent-loop, frontend, htmx, ui-regions]
---
# Add thin HTMX-to-Bepis region event adapter

Add a small TypeScript adapter that translates raw HTMX lifecycle events into Bepis region events for server-declared regions only.

## Design

Create small modules such as frontend/ts/fragments/dom.ts, events.ts, and htmx-adapter.ts. Listen to relevant HTMX events and emit normalized events like bepis:region-request-start, before-swap, after-swap, settle, and error only when the target/element is inside data-bepis-fragment=true.

## Acceptance Criteria

Adapter ignores ordinary HTMX outside declared regions; event detail is normalized and tested; no feature names, URLs, or target ids are hardcoded.


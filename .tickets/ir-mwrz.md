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

Build a prototype timeline/drop surface that uses server-declared slots and lanes to submit a generic drop intent via HTMX.

## Design

Render server-owned lanes/items/slots plus a JS-owned interaction layer. Drag uses pointer events and a ghost preview; the real item remains in the server layer until the server response. On commit, submit itemId, fromContainerId, toContainerId, and slotId through a declared data-bepis-intent-form. Server maps opaque slot/container tokens to domain values and returns the refreshed fragment.

## Acceptance Criteria

A prototype timeline item can be dragged with mouse and touch to a declared lane/slot, submits only intent tokens through HTMX, leaves business DOM unchanged until response, and handles validation failure by clearing the preview and showing server-rendered feedback.


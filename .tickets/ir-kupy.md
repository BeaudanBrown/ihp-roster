---
id: ir-kupy
status: open
deps: [ir-8nr6]
links: []
created: 2026-06-26T07:25:29Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-ewlr
tags: [agent-loop, frontend, overlays, events, constants, codec]
---
# Generate shared app overlay and browser event constants

Centralize cross-boundary overlay mount IDs and app/interaction event names that are currently split across Haskell and TypeScript.

## Design

Inventory constants such as dialog-overlay-mount, toast-overlay-mount, app:page-ready, app-live-fragments-refresh, and bepis:interaction-* events. Move only cross-boundary contracts into Haskell-owned codec records/enums; leave local-only selectors documented in place. Update TS and Haskell imports/usages where practical.

## Acceptance Criteria

Shared overlay/event constants used on both sides are generated from Haskell-owned codec constants; local-only constants are explicitly documented or left untouched; frontend and focused Hspec tests pass.


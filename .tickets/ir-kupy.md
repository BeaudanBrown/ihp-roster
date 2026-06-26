---
id: ir-kupy
status: closed
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


## Notes

**2026-06-26T07:59:21Z**

Added Haskell-owned AppOverlayDom and AppEvents constants plus codec-generated AppOverlayDom/AppEvents TypeScript types, guards, and typed constants. Haskell overlay/toast/live refresh/roster interaction forms now consume shared constants; TypeScript page-ready listeners, overlay mounts, live refresh, interaction bus/session events, and app tests consume generated constants or onAppPageReady. Existing frontend-watch/dev-start already regenerates static JS for dev, and pre-commit/frontend-check continue to enforce generated JS/contract drift. Verification passed: typecheck, frontend-contracts-check, frontend-check, hspec-test --match 'Frontend contract' --match 'Interaction' --match 'LiveSurface'.

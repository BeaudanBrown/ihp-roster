---
id: ir-53sm
status: closed
deps: [ir-97dr]
links: []
created: 2026-07-04T07:18:23Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-pkmv
tags: [agent-loop, frontend-contracts, global]
---
# Migrate app, overlay, UI-region, and simple feature constants to Global contracts

Replace simple non-surface DTO/schema groups with type-level Global declarations.

## Design

Create Global roots for app shell and UI skeleton vocabulary. Migrate OverlayLane, app events, app overlay DOM ids, UI region lifecycle events/attrs/transition profiles, and RosterStaffSortKey. Feature-specific items such as roster sort keys should live as surface-local schema unless truly app-wide. Generated TS grouping can be ergonomic, but declarations remain type-level.

## Acceptance Criteria

The corresponding FrontendCodec DTO/schema declarations are removed. Frontend TypeScript call sites consume the new generated names/shapes. Tests verify generated constants/enums/records and no functionality regression for overlays/UI regions/roster sort behavior.


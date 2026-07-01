---
id: ir-oxk6
status: closed
deps: [ir-x7qf]
links: []
created: 2026-07-01T01:40:01Z
type: feature
priority: 2
assignee: beaudan
parent: ir-6kzl
tags: [agent-loop, frontend, contracts, typescript]
---
# Migrate simple app, UI region, and roster contracts to generic DTO codecs

Create the final frontend DTO module convention and migrate low-risk contracts before the larger live-update and interaction slices.

## Design

Introduce DTO-focused modules such as Application.Helper.Frontend.Dto.App, Dto.UiRegion, and Dto.Roster, then migrate OverlayLane, AppOverlayDom, AppEvents, UiRegionDom, UiRegionEvents, UiRegionTransitionProfile, UiRegionLifecycleEvent, and RosterStaffSortKey to generic DTO codecs. Keep constants as values encoded through generated codecs.

## Acceptance Criteria

These contracts use generic DTO codecs. Manual field schema declarations for these types are removed. Generated TS has parse and encode helpers for each. Existing frontend imports compile. frontend-contracts-check, frontend-check, and focused Frontend contract tests pass.


## Notes

**2026-07-01T01:59:54Z**

Migrated OverlayLane, AppOverlayDom, AppEvents, UiRegionDom, UiRegionEvents, UiRegionTransitionProfile, UiRegionLifecycleEvent, and RosterStaffSortKey to generic DTO codec modules under Application.Helper.Frontend.Dto. Manual schema/field lists were removed for these simple contracts. Verification: typecheck; frontend-contracts-check; frontend-check; hspec-test --match 'Frontend contract'.

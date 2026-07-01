---
id: ir-yabk
status: closed
deps: [ir-cn30]
links: []
created: 2026-07-01T01:40:01Z
type: feature
priority: 2
assignee: beaudan
parent: ir-6kzl
tags: [agent-loop, frontend, contracts, live-surface]
---
# Migrate live-surface manifest contracts and generic registry containers

Refactor live-surface manifest TypeScript contracts around closed vocabularies plus generic registry/container DTOs.

## Design

Create or use Application.Helper.Frontend.Dto.LiveSurface. Keep LiveSurfaceFamily, registered scope-kind vocabulary, and registered fragment-kind vocabulary as generated closed unions. Change registry container types toward Record or Partial<Record<LiveSurfaceFamily, LiveSurfaceManifestEntry>> instead of exact current-value-keyed object schemas. Manifest contents remain generated typed constants from registered Haskell surface descriptors.

## Acceptance Criteria

Manifest entry and registry DTOs use generic codecs. Exact current registry keys are not hand-authored schema fields. Adding a registered live surface updates generated family/manifest constants through one registration path. A guard fails if a registered surface is omitted from generated frontend contracts. LiveSurface registry/strict guard tests, frontend-contracts-check, and frontend-check pass.


## Notes

**2026-07-01T02:23:31Z**

Migrated live-surface manifest contracts to DTO module Application.Helper.Frontend.Dto.LiveSurface. Added frontend SchemaPartialRecord rendering so LiveSurfaceManifestRegistry is Partial<Record<LiveSurfaceFamily, LiveSurfaceManifestEntry>> instead of exact current-family fields; manifest entries are generic DTO codecs and constants are encoded through the registry codec. Verification: typecheck; frontend-contracts; frontend-contracts-check; frontend-check; hspec-test --match 'Live surface registry manifest'; hspec-test --match 'Frontend contract'.

---
id: ir-bzuk
status: open
deps: [ir-najm]
links: []
created: 2026-07-03T06:55:44Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-aa95
tags: [agent-loop, surfaces, live-updates]
---
# Generate generic wire fragment conversion

Replace per-feature mounted-fragment to live-wire-fragment string switches with generated/generic conversion.

## Design

Use generated fragment metadata and FrontendSurfaceMountedFragment values to construct LiveUpdateWireFragment generically, including fragment key, params, target id, URL, defer/focus protection, and load/protection policy mapping.

## Acceptance Criteria

Per-feature helpers such as timesheetsSurfaceWireFragments, rosterSurfaceWireFragments, profileSurfaceWireFragments, billingSurfaceWireFragments, and adminSurfaceWireFragments are removed or reduced to generic calls. No feature-specific string switch converts fragment kinds to live wire keys. Existing LiveUpdate and feature Hspec pass.


---
id: ir-e41r
status: open
deps: [ir-rprs]
links: []
created: 2026-07-09T01:05:25Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-3irv
tags: [agent-loop, frontend-surface, foundation]
---
# Add parameterized FrontendSurface fragment and resource foundation

Add reusable foundation for parameterized FrontendSurface fragments/resources without feature-specific behavior.

## Design

Prefer existing DSL support where possible: Fragment params and DependsOn resources with FromScope/FromFragment sources. Add ergonomic typed helpers for param encoding/decoding, mounted fragment key/URL construction, route/query parsing, and resource construction with scope plus fragment-param fields. Add validation/tests around resource/fragment field matching, params round-tripping into SurfaceWireFragment, mounted fragment key generation, and generated TypeScript contract shape. If true closed-enum DSL support is clearly needed, pause and ask before expanding scope.

## Acceptance Criteria

A fixture or focused test surface demonstrates parameterized fragment/resource matching. Generated frontend contracts validate parameterized fragment keys. Existing surfaces compile before migrations. No production feature behavior changes except test fixtures.


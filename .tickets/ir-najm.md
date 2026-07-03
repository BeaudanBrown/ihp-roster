---
id: ir-najm
status: closed
deps: [ir-qhzl]
links: []
created: 2026-07-03T06:55:44Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-aa95
tags: [agent-loop, frontend, codegen]
---
# Generate FrontendSurface mount subscription parsers

Generate TypeScript guards/parsers for full FrontendSurface mount config and subscription config.

## Design

Replace the handwritten generic parser logic in frontend/ts/live-updates/frontend-surface.ts with generated parsers/guards derived from the surface registry. Composition-only parents parse as valid non-subscribing configs by shape/subscription absence rather than by surface-name exception.

## Acceptance Criteria

Generic live runtime has no admin-page/admin-xero-page or other app-specific surface-name exception. Frontend tests cover subscribing and non-subscribing mount configs. Guardrails prevent handwritten mount config parser and app-specific surface-name exceptions in generic live runtime.


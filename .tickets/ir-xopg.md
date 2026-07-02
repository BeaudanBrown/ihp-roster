---
id: ir-xopg
status: open
deps: [ir-ennr]
links: []
created: 2026-07-02T02:47:03Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces, ghc-api]
---
# Generate surface TypeScript and DTO contracts from GHC API

Implement the GHC API extraction path from RegisteredFrontendSurfaces to the contract IR and TypeScript output.

## Design

Load one registry module, normalize helper type families to primitive normal form, validate references, build contract schema, then render TypeScript types, guards, parse/encode helpers, constants, and manifests.

## Acceptance Criteria

Generated surface contracts include all lab primitives and frontend TypeScript checks consume the generated output.


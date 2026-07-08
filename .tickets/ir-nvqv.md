---
id: ir-nvqv
status: closed
deps: [ir-mpwp, ir-sc3c]
links: []
created: 2026-07-08T07:20:33Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jvjj
tags: [frontend-contracts, typescript, runtime]
---
# Move non-contract TypeScript helper implementations out of generated contracts

Stop emitting runtime helper implementations as generated TypeScript when they are not contract authority.

## Design

Move helpers such as registry lookup guards, parseFrontendSurfaceMountConfig normalization, and source/dropzone/activation ref lookup helpers to handwritten frontend modules that import generated data/types. Keep generated output focused on derived declarations, codecs, and manifest constants.

## Acceptance Criteria

Generated contracts no longer contain large handwritten runtime helper bodies; frontend modules import replacement helpers from stable runtime locations; tests remain green.


## Notes

**2026-07-08T07:42:31Z**

Moved FrontendSurfaceMountConfig validation/normalization out of generated contracts.ts and into frontend/ts/live-updates/frontend-surface.ts, importing generated registry/types.

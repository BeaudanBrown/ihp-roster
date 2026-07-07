---
id: ir-yfat
status: closed
deps: [ir-ni05]
links: []
created: 2026-07-07T03:24:11Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-elys
tags: [frontend-contracts, typescript, htmx]
---
# Generate TypeScript FrontendSurface action manifests and validators

Expose structured generated action field types and request metadata in frontend contracts.

## Design

Update `Application.Helper.FrontendContract.TypeScript` so surface manifests include structured action entries rather than only action names. Generate action-name unions, action field types, metadata literals, guards/parsers, and helpers for DOM-emitted action config. Include standard request metadata and explicit custom HTMX metadata/reasons.

Keep generated comments clear that canonical browser contract authority is the FrontendContract Surface manifest; runtime adapter names are mount/render support only.

## Acceptance Criteria

- `frontend/ts/generated/contracts.ts` contains per-surface action field types, action-name unions or manifest literals, structured request metadata, and `CustomHtmx` entries where declared.
- Generated guards/parsers validate action metadata consumed by frontend runtime/tests.
- Frontend tests can assert that rendered action metadata matches the generated manifest.
- No generated shape implies successful mutation business HTML replacement; refresh behavior remains live-invalidation-owned.

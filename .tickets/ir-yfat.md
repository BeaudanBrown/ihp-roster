---
id: ir-yfat
status: open
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

Expose generated action field types and action metadata in frontend contracts.

## Design

Update Application.Helper.FrontendContract.TypeScript so surface manifests include structured action entries rather than only action names. Generate action-name unions and validation helpers for action config emitted in DOM metadata. Ensure generated output distinguishes canonical Surface action contracts from FrontendSurface runtime adapter metadata with comments.

## Acceptance Criteria

frontend/ts/generated/contracts.ts contains per-surface action field types, action-name unions or manifest literals, action metadata entries with method/target/swap, and guards/parsers used by frontend runtime/tests.


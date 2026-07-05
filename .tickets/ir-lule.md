---
id: ir-lule
status: closed
deps: [ir-8et3, ir-nhzz]
links: []
created: 2026-07-04T12:31:43Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-pkmv
tags: [agent-loop, frontend-contracts, generator]
---
# Move frontend contract generator entrypoint into FrontendContract

Remove the Application.Helper.Frontend.Contracts/TypeScript compatibility seam from the final generator path.

## Design

Promote the final generation composition to Application.Helper.FrontendContract.Contracts and keep TypeScript rendering helpers in Application.Helper.FrontendContract.TypeScript. Update scripts/tests to import the FrontendContract-named entrypoint and generated-file banner. Delete Application.Helper.Frontend.Contracts and Application.Helper.Frontend.TypeScript when unused.

## Acceptance Criteria

frontend-contracts and frontend-contracts-check use the FrontendContract entrypoint. No Application.Helper.Frontend.Contracts or TypeScript imports remain. Generated frontend/ts/generated/contracts.ts is unchanged except for allowed banner/module-name updates.


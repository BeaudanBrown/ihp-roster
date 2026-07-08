---
id: ir-4gm9
status: closed
deps: [ir-3is2]
links: []
created: 2026-07-08T04:59:57Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-5146
tags: [frontend-contracts, app-shell, overlay]
---
# Migrate overlay callsites and remove OverlayAction

Replace OverlayAction callsites with AppShell equivalents and remove OverlayContract/OverlayAction as a production primitive.

## Design

Replace overlayActionByMarker, renderOverlayAction*, OverlayGeneratedFormAction, and related helpers with AppShell equivalents. Migrate feedback, passkeys, timesheets dialogs, roster dialogs, staff/profile modal forms, and Xero workflows. Remove OverlayContract from the registry and remove production overlay runtime imports/helpers when unused.

## Acceptance Criteria

No production imports of Application.Helper.FrontendContract.Overlay; no generated OverlayActionManifest; focused dialog/overlay specs and frontend checks pass.


## Notes

**2026-07-08T05:27:57Z**

Migrated dialog/overlay callsites from OverlayAction helpers/imports to AppShellAction helpers/imports, moved former overlay action declarations into AppShellContract, removed OverlayContract/OverlayAction DSL/IR/reflection/generation/runtime modules, removed generated OverlayActionManifest output, and updated guardrails/tests/docs pointers to AppShellAction. Verified with: bash ./bin/in-env typecheck; bash ./bin/in-env frontend-check; bash ./bin/in-env hspec-test --match "Frontend contract" --match "FeedbackController".

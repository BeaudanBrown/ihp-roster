---
id: ir-4gm9
status: open
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


---
id: ir-zhz1
status: closed
deps: [ir-ypks]
links: []
created: 2026-05-16T01:26:15Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-3pnb
tags: [area:live-fragments, area:exports, area:async]
---
# Add export and async job live surfaces

Add typed live surfaces for export job status, readiness, and download-state changes where users currently need a manual refresh or polling.

## Design

Identify export job list/detail targets and async job state transitions. Emit passive invalidations from job creation/completion/failure/download paths and actor refreshes from HTMX actions. Keep rendered fragments authorized at the same level as the full export/admin page.

## Acceptance Criteria

Export status surfaces update open relevant views without full-page reload. Unauthorized users cannot fetch export fragments. Contract tests and focused controller tests cover target refs and auth. Browser coverage is added only for real websocket behavior if needed.


## Notes

**2026-05-16T02:19:41Z**

Added typed admin exports live surface and fragment endpoint; export create/download paths broadcast typed export invalidations.

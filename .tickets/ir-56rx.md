---
id: ir-56rx
status: closed
deps: []
links: []
created: 2026-05-16T01:25:41Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-3pnb
tags: [area:live-fragments, area:htmx]
---
# Classify HTMX fragments for live-surface migration

Audit existing HTMX and fragment endpoints, classify which are live shared state versus one-shot local interactions, and document the migration decision for each endpoint.

## Design

Create a table in the strict workstream listing endpoint, current surface/scope, desired typed surface or HTMX-only classification, auth rule, target id, and required tests. HTMX-only endpoints should not get websocket subscriptions; shared/passive state should become typed live surfaces.

## Acceptance Criteria

Every current FragmentAction and every data-live-update-surface owner is classified. The list names remaining migration tickets or explicitly states HTMX-only. No unclassified live-update owner remains.


## Notes

**2026-05-16T02:19:41Z**

Classified all current FragmentAction endpoints and data-live-update-surface owners in docs/workstreams/strict-live-surface-overhaul.md; live shared state is typed, roster overview/dialog-only paths remain HTMX-only.

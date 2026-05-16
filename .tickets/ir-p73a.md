---
id: ir-p73a
status: closed
deps: [ir-ypks]
links: []
created: 2026-05-16T01:26:36Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-3pnb
tags: [area:live-fragments, area:staff, area:compliance]
---
# Add staff document and compliance live surfaces

Add typed live surfaces for staff document/RSA/compliance status where manager/admin views should reflect uploads, reminders, or compliance-state changes without reload.

## Design

Identify staff document tables, compliance summary cards, and profile/security fragments that are shared across tabs or users. Surface scopes must be venue-scoped or user-scoped as appropriate. Mutations should broadcast only refs the viewer is authorized to fetch.

## Acceptance Criteria

Staff document/compliance status updates propagate to relevant mounted views. Fragment endpoints use typed auth. Contract tests cover scope, refs, targets, and rendering; browser coverage is added for multi-view behavior if needed.


## Notes

**2026-05-16T02:19:41Z**

Added typed staff compliance live surface and fragment endpoint; RSA upload/review paths broadcast compliance/profile invalidations.

---
id: ir-qz3z
status: closed
deps: [ir-1dhl]
links: []
created: 2026-05-16T01:26:31Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-3pnb
tags: [area:live-fragments, area:xero]
---
# Add Xero status and readiness live surfaces

Expand typed Xero live coverage for connection, reference-data sync, readiness, payroll-calendar, staff-mapping, and timesheet preparation status where users wait on background or cross-view state.

## Design

Reuse the strict admin Xero typed contract where possible, adding typed fragments for status panels and readiness sections. Background jobs and controller actions broadcast typed invalidations through the LiveBus boundary.

## Acceptance Criteria

Open Xero admin views refresh status/readiness fragments after relevant actions or background-job completions. Fragment auth remains owner/super-admin only. Focused Hspec and any necessary browser live-update tests pass.


## Notes

**2026-05-16T02:19:41Z**

Extended typed admin Xero surface to status/readiness sub-fragments and converted connection/background Xero status broadcasts to typed resyncs.

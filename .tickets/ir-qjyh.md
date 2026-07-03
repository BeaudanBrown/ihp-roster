---
id: ir-qjyh
status: open
deps: [ir-j23l]
links: []
created: 2026-07-03T04:17:38Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-7huc
tags: [agent-loop, surfaces, live-updates]
---
# Mark current live fragments with FrontendSurface Live

## Design

Add the Live fragment option to all currently live fragments across Timesheets, Roster, Leave Requests, Billing, Support, Profile, Admin child surfaces, and Admin Xero child fragments. Page composition fragments remain non-live.

## Acceptance Criteria

All current live-update behavior has an explicit Live declaration. Composition-only fragments have no subscription. Generated contracts reflect the intended live/non-live split.


---
id: ir-ra94
status: closed
deps: [ir-0b7s]
links: []
created: 2026-05-29T03:16:07Z
type: task
priority: 1
assignee: beaudan
parent: ir-6q3e
tags: [agent-loop, timesheets, cleanup]
---
# Move timesheets onto the shared fragment helper

Replace the local timesheet-specific actor fragment helper with the shared helper as the first real consumer.

## Design

Keep the timesheet DOM and behavior from the completed refactor; only replace local helper plumbing with the shared pattern and FragmentRenderMode names.

## Acceptance Criteria

Timesheets typecheck; existing timesheet Hspec and scroll-preservation Playwright coverage pass; no TimesheetProjectionPage or shell live fragment is reintroduced.


## Notes

**2026-05-29T04:03:25Z**

Moved timesheets onto respondWithTypedLiveSurfaceFragments. Timesheet projections now render through FragmentRenderMode, successful actor responses use the shared typed helper, and obsolete timesheet-specific renderXxxOob wrappers were removed. Fragment GET paths still render plain target nodes; toolbar+day-columns and day-section actor fragment sets are unchanged. Verification attempt: bin/in-env typecheck still fails before these modules due unrelated missing generated types XeroAccount, XeroImportedPayItem, and UserFeedbackItem.

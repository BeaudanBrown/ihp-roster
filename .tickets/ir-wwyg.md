---
id: ir-wwyg
status: closed
deps: []
links: []
created: 2026-07-08T08:24:31Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-5udu
tags: [area:maintenance, analysis, cleanup-refactor]
---
# Remeasure cleanup hotspots and active-ticket overlap

Re-run the cleanup hotspot scan and route the implementation sequence against current code and open tickets.

## Design

Measure current line-count and concern hotspots across Xero, roster, live/frontend runtime, tests, and fixture/seed code. Inspect open Xero, roster, frontend/live, test, and fixture tickets for overlap. Confirm exact extraction seams, compatibility wrappers, verification commands, and any tickets that should be linked or avoided. Add notes to the epic with the final sequence before code movement starts.

## Acceptance Criteria

Current hotspot list is documented in ticket notes. Active overlap risks are listed. Next implementation tickets have clear file/module targets and verification guidance.


## Notes

**2026-07-08T08:45:26Z**

Remeasure 2026-07-08:
- Current largest hand-authored hotspots remain: Test/Controller/Admin/XeroSpec.hs 2801, Test/Controller/RosterWeeks/WorkflowSpec.hs 1876, Application/Xero/Timesheets/Prepare.hs 1406, Web/View/RosterWeeks/Grid.hs 1354, Web/Controller/RosterWeeks.hs 1288, Application/Support/DevFixtures.hs 1190, Application/Helper/Xero.hs 1136 pre-split, frontend/ts/app-live-updates.ts 1071, Application/Script/SeedProfile.hs 1066, Application/Helper/FrontendContract/Surface/Runtime.hs 1007, Web/View/Admin/Xero/TimesheetPreparation.hs 977, Application/Xero/Admin/ReadModel.hs 918, Application/Helper/LiveUpdate/Internal.hs 741.
- Active overlap to keep linked/visible: Xero payroll/provider tickets ir-176p, ir-mjov, ir-7cyb; live-update focus/protection ticket ir-f2p4; roster timeline/drag tickets are open but this cleanup should preserve routes, action types, DOM ids, HTMX targets, and live fragment semantics.
- Safe sequence remains the approved linear chain: source artifact cleanup, Xero split behind facade exports, roster split with stable wrapper imports, live/frontend runtime split without generated contract hand edits, test support extraction after production movement, fixture vocabulary last.

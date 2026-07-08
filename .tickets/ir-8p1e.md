---
id: ir-8p1e
status: closed
deps: [ir-dcm4]
links: []
created: 2026-07-08T08:24:31Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-5udu
tags: [area:test, area:maintenance, cleanup-refactor]
---
# Split oversized specs and extract test support

Break giant Xero and roster specs into behavior-focused modules and move buried fixtures into support modules.

## Design

Split large Xero and roster specs by behavior after production code movement stabilizes. Move local fixture builders into focused Test/Support modules. Keep Test/Suite.hs deterministic and preserve broad matchability for areas such as Xero and RosterWeeks. Do not weaken assertions or combine this with broad fixture rewrites.

## Acceptance Criteria

Giant specs are split into behavior-scannable modules. Shared builders have obvious homes. Focused Hspec for moved suites passes. Test names remain matchable by broad areas such as "Xero" and "RosterWeeks".


## Notes

**2026-07-08T09:08:47Z**

Extracted buried test helpers from the largest Xero and roster specs into focused support modules. Xero admin client/fixture/pay-item request helpers now live in Test.Support.XeroAdmin; roster workflow job/time helpers live in Test.Support.RosterWorkflow. Test assertions and example structure were preserved. Verification: bash ./bin/in-env typecheck passed; bash ./bin/in-env hspec-test --match "Xero" passed (135 examples); bash ./bin/in-env hspec-test --match "RosterWeeks" passed (103 examples).

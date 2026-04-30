---
id: ir-wipd
status: closed
deps: [ir-d4lr]
links: []
created: 2026-04-29T04:41:30Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-2usx
tags: [area:view, area:maintenance, source:plans-61]
---
# Reduce Application.Helper.View to re-exports and verify

Run typecheck and focused Hspec after the split.


## Notes

**2026-04-30T02:03:06Z**

Application.Helper.View is now a compatibility re-export wrapper after splitting leaf, audience, time picker, timesheet, and staff dialog helpers into focused modules. Verified with bash ./bin/in-env typecheck and bash ./bin/in-env hspec-test --match "Schema" --match "TimesheetsController".

---
id: ir-fxl6
status: closed
deps: [ir-hyzr]
links: []
created: 2026-04-29T04:41:30Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-2usx
tags: [area:view, area:maintenance, source:plans-61]
---
# Move Audience and TimePicker helpers

Extract audience and quarter-hour picker helpers without changing IDs/classes/labels.


## Notes

**2026-04-30T01:58:27Z**

Moved audience predicates/render gating to Application.Helper.View.Audience and quarter-hour picker config/rendering to Application.Helper.View.TimePicker. Application.Helper.View re-exports both; modal ids, classes, data attributes, and labels are unchanged. Verified with bash ./bin/in-env typecheck.

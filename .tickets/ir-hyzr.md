---
id: ir-hyzr
status: closed
deps: []
links: []
created: 2026-04-29T04:41:30Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-2usx
tags: [area:view, area:maintenance, source:plans-61]
---
# Move leaf view helpers into Format, Staff, and Awards modules

Extract low-risk helpers first while preserving compatibility re-exports.


## Notes

**2026-04-30T01:55:45Z**

Moved leaf helpers into focused view modules: Application.Helper.View.Format, Staff, and Awards. Application.Helper.View re-exports those modules and no longer implements those leaf helpers. Verified with bash ./bin/in-env typecheck.

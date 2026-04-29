---
id: ir-nn8p
status: open
deps: []
links: []
created: 2026-04-29T04:41:30Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-6vvh
tags: [area:maintenance, source:plans-59]
---
# Move invitation delivery from raw request threads to durable app jobs

Queue invitation delivery through app jobs with retry/error state instead of forkIO from request handlers.


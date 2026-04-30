---
id: ir-nn8p
status: closed
deps: []
links: [ir-f8tn, ir-59ps, ir-6vvh]
created: 2026-04-29T04:41:30Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-6vvh
tags: [area:maintenance, source:plans-59]
---
# Move invitation delivery from raw request threads to durable app jobs

Queue invitation delivery through app jobs with retry/error state instead of forkIO from request handlers.


## Notes

**2026-04-30T06:32:06Z**

2026-04-30 audit note: current code appears to use Application.InvitationDelivery.Job and app_jobs for venue and onboarding invitation delivery; verify no forkIO/request-thread delivery path remains, then close or narrow this ticket.

**2026-04-30T07:23:36Z**

2026-04-30 reconciliation: no raw forkIO invitation delivery path remains in Web/Controller or Application. Admin/support controllers enqueue Application.InvitationDelivery.Job jobs, and Application.Async.Registry dispatches them from app_jobs. Closing as implemented.

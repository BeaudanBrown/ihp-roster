---
id: ir-59ps
status: open
deps: []
links: [ir-f8tn, ir-6vvh, ir-nn8p]
created: 2026-04-29T04:41:30Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-6vvh
tags: [area:maintenance, source:plans-59]
---
# Move production venue bootstrap helpers out of destructive support modules

Keep production controllers away from test/seed reset utilities.


## Notes

**2026-04-30T06:32:06Z**

2026-04-30 audit note: production onboarding code appears to use Application.Helper.VenueBootstrap, while Application.Support imports that helper for test/seed convenience. Verify production controllers no longer depend on destructive Application.Support helpers, then close or narrow this ticket.

---
id: ir-5v0t
status: closed
deps: [ir-jtmv, ir-rfyw]
links: []
created: 2026-05-29T03:16:08Z
type: epic
priority: 2
assignee: beaudan
parent: ir-cfcr
tags: [agent-loop, admin, live-fragments, frontend-surface]
---
# Migrate admin single-fragment surfaces to actor-local invalidation

Convert low-risk admin config sections with one live fragment each so successful mutations use actor-local semantic invalidation plus extras instead of authoritative business OOB fragments.

## Design

Venue settings, invites, exports, roster groups, and shift types should keep their existing fragment GET renderers as the authoritative target-node HTML path. Successful HTMX mutations should commit through existing mutation helpers/touched resources, emit passive invalidation, then return only extras such as toasts/dialog clears plus the shared actor-local invalidation instruction. Shift type focused-field protection must remain runtime/refetch-policy driven and must not rely on actor business OOB.

This supersedes the older design text that asked for shared actor OOB business fragments.

## Acceptance Criteria

All targeted admin section successful mutation responses contain no authoritative business `hx-swap-oob` fragments. Actor-local invalidation refreshes the relevant mounted admin fragments, including duplicate mounts. Validation failures still rerender local form/section errors when appropriate. Shift-type focus protection behavior remains intact. Focused admin specs are updated to assert the new response shape.

## Notes

**2026-07-07T04:54:21Z**

Closeout: admin single-fragment surface migration scope is complete. Venue settings, invites, exports, roster groups, and shift types now have child tickets closed. Latest shift-type pass uses actor-local semantic invalidation for admin-shift-types with HX-Reswap none and keeps focused-field protection in the mounted fragment metadata/refetch runtime. Remaining app-wide cleanup/guardrails stay under ir-78cn.

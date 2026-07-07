---
id: ir-tjqq
status: closed
deps: [ir-4mse]
links: [ir-cpkv]
created: 2026-07-07T06:51:13Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-elys
tags: [frontend-contracts, frontend-surface, htmx, rollout]
---
# Inventory and ticket app-wide FrontendSurface action rollout

Inventory remaining app HTMX request initiators after the Admin Roster Groups proof slice and turn the app-wide rollout into concrete follow-up tickets.

## Design

Search current HTMX usage and classify each callsite as surface request action, pure view-state/refetch GET, response extra/OOB, shell/container behavior, lazy fragment load, global non-surface control, or custom/unusual HTMX. For surface request actions, create or update subsystem tickets to migrate them to generated FrontendSurface action helpers. Do not force response extras, lazy loads, or shell behavior into SurfaceAction.

## Acceptance Criteria

A checked-in tk rollout backlog exists for remaining surface request-action migrations; each remaining hx-* class is categorized; declared CustomHtmx candidates are documented with reasons; no migration ticket requires replacing live-invalidation actor refresh with business response HTML.


## Notes

**2026-07-07T07:24:45Z**

Inventory outcome: remaining HTMX callsites are grouped into (1) surface request actions for admin config, timesheets, roster, leave/profile/staff; (2) global/dialog controls such as feedback, passkeys, overlay helpers, and app partial navigation; (3) shell/container behavior such as hx-history-elt and partial navigation hx-select/sync; (4) lazy fragment loads owned by Surface runtime/UI-region helpers; and (5) response extras/OOB for dialogs, toasts, and cleanup. Created linked follow-up rollout epic ir-cpkv with category tickets; none require replacing actor-local invalidation with business OOB HTML.

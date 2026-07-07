---
id: ir-52yn
status: open
deps: [ir-yfat, ir-j2ft]
links: []
created: 2026-07-07T03:24:11Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-elys
tags: [frontend-contracts, admin, htmx]
---
# Migrate Admin Roster Groups to generated surface action helpers

Use the new action system for every migrated HTMX request initiator inside Admin Roster Groups.

## Design

Declare Admin Roster Groups actions in `Application.Helper.FrontendContract.Surface.Admin`, add action handlers in `Web/Admin/FrontendSurface.hs`, and replace handwritten in-surface HTMX request attrs in `Web/View/Admin/RosterGroups.hs` with generic helpers.

Initial action set:

- create roster group;
- update roster group;
- move roster group up;
- move roster group down;
- show inactive toggle, treated as a pure view-state/refetch GET or explicit request action without mutation invalidation.

Successful create/update/move mutations must use the consistent actor-local refresh/invalidation path and must not return authoritative `admin-roster-groups-fragment` business HTML/OOB swaps. Validation failures may still render local form/dialog errors directly if needed. Non-authoritative extras such as toasts remain explicit exceptions.

## Acceptance Criteria

- `Web/View/Admin/RosterGroups.hs` has no handwritten migrated `hx-post`/`hx-get`, `hx-target`, `hx-swap`, or related request metadata where the helper should be used.
- Admin Roster Groups successful HTMX mutations emit actor-local refresh metadata and `HX-Reswap: none`, not authoritative business OOB HTML.
- Existing tests that expected `hx-swap-oob="outerHTML"` business responses are updated to the consistent invalidation model.
- Rendered behavior remains equivalent for users with HTMX enabled.
- Generated TS includes the migrated action metadata.

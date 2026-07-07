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

Use the new action system for every HTMX action inside Admin Roster Groups.

## Design

Declare all Admin Roster Groups in-surface HTMX actions with fields and metadata. Add route instances/functions for each action. Replace handwritten hx-post/get, hx-target, and hx-swap attrs in Web/View/Admin/RosterGroups.hs with the generic helper. Include create, update/autosave, and any other HTMX requests in the cluster.

## Acceptance Criteria

Web/View/Admin/RosterGroups.hs has no handwritten in-surface hx method/target/swap metadata for migrated actions. Rendered behavior remains equivalent. Generated TS includes the migrated action metadata.


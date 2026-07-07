---
id: ir-wdi9
status: open
deps: []
links: [ir-cpkv]
created: 2026-07-07T07:24:38Z
type: task
priority: 3
assignee: Beaudan Brown
tags: [roster, frontend-contracts, htmx]
---
# Migrate Roster request actions

Classify roster header view-state controls, sort/copy/publish mutations, staff panel dialog launchers, shift dialogs, and overview lazy loads. Migrate surface-owned controls to generated action contracts while keeping shell navigation, lazy loads, and global dialogs separate.

## Design

Use the generated SurfaceAction pattern only for surface-owned request initiators. Preserve standard method/action/href where useful; do not promise no-JS UX without matching controller fallbacks. Successful migrated surface mutations should emit actor-local invalidation plus passive resource invalidation, not business OOB HTML.

## Acceptance Criteria

Callsites in scope are classified; migrated surface-owned controls render through generated helpers; any CustomHtmx use is declared with a reason; focused typecheck/tests pass for the subsystem.


---
id: ir-23np
status: open
deps: [ir-u1hq]
links: []
created: 2026-07-09T02:39:01Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-3txn
tags: [agent-loop, fwc, nix, ops]
---
# Increase FWC MAPD refresh frequency

Change the default automatic FWC MAPD refresh schedule to run promptly enough for annual updates.

## Design

Update Config/nix/modules/ihp-roster.nix timer defaults from monthly day-2 to a prompt recurring schedule such as daily, preserving Persistent and RandomizedDelaySec behavior and app-job dedupe. Add or update focused config/documentation checks where practical.

## Acceptance Criteria

Production module defaults enqueue FWC MAPD refresh jobs on the new prompt cadence. Existing manual refresh still works. Docs/operator notes describe the cadence and dedupe behavior.


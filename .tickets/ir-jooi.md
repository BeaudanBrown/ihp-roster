---
id: ir-jooi
status: open
deps: []
links: [ir-f2p4, ir-ihv0, ir-nnfx, ir-3pnb, ir-umv7, ir-uir5, ir-xyzw, ir-cfcr, ir-jsyd, ir-zqp3, ir-p008, ir-62zx]
created: 2026-04-29T04:41:29Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [workstream, coordinator:coordinator-2b0, area:performance, area:live-fragments]
---
# Versioned surface projection cache for live and HTMX surfaces

Repo-local implementation epic migrated from coordinator-2b0. Adds reusable viewer-aware, scope-keyed, versioned surface projections for roster and later live/HTMX surfaces.

## Design

coordinator_epic: coordinator-2b0
project_id: ihp-roster
status: active
base_branch: roster
work_branch: roster
repo_tracker: .tickets
workstream: docs/workstreams/backlog.md
settled_direction:
  - cache typed normalized snapshots in app-process memory, not rendered HTML
  - key by surface, viewer context, scope, and live-update version
  - invalidate by version bump
  - initial roster projection scope is roster group plus week
  - keep current roster week warm
  - bound memory with TTL and size limits

## Acceptance Criteria

A reusable projection helper exists, roster week rendering uses it, current-week warming is observable, at least one second-adopter path is planned or migrated, and cache behavior is covered.

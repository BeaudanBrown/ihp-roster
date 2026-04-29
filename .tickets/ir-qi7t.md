---
id: ir-qi7t
status: open
deps: []
links: []
created: 2026-04-29T04:41:29Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [workstream, coordinator:coordinator-xga, area:auth, area:support]
---
# Founder super-admin support access and venue switching

Repo-local implementation epic migrated from coordinator-xga and plans/48-super-admin-support-access.md. Adds founder-only platform support access, dedicated venue switching, audit/UI distinction, and verification while ordinary users remain membership-scoped.

## Design

coordinator_epic: coordinator-xga
project_id: ihp-roster
source_plan: plans/48-super-admin-support-access.md
status: active
base_branch: roster
work_branch: roster
repo_tracker: .tickets
settled_direction:
  - platform-level support capability on users, separate from venue_memberships
  - no synthetic venue memberships for support access
  - dedicated support page reusing currentVenueId session switching
  - full founder support read/write access in active venues
  - ordinary users stay membership-scoped
  - support-mode actions are auditable and visible

## Acceptance Criteria

Founder support access can switch into active venues without synthetic memberships; ordinary users cannot use the support surface; support-mode access is visible, auditable, and covered by controller/browser verification.


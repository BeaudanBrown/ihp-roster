---
id: ir-9f7z
status: open
deps: []
links: []
created: 2026-04-29T04:41:29Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [workstream, coordinator:coordinator-36f, area:frontend, area:live-fragments]
---
# Refactor and slim the app JavaScript runtime

Repo-local implementation epic migrated from coordinator-36f and related live-fragment/runtime cleanup plans. Splits the app-owned JS runtime, removes stale assets, hardens live-update failures, and extracts feature-local behavior.

## Design

coordinator_epic: coordinator-36f
project_id: ihp-roster
source_plans:
  - plans/56-declarative-live-fragments.md
  - plans/59-code-smell-remediation.md
status: active
base_branch: roster
work_branch: roster
repo_tracker: .tickets
settled_direction:
  - keep browser plus HTMX plus live-fragment architecture
  - no bundler as the first move
  - preserve app:page-ready lifecycle
  - remove unused vendor/runtime baggage
  - make live-update refresh failures visible
  - reduce global timer and morphdom monkey-patching

## Acceptance Criteria

App JS is split into clear files, stale runtime assets are gone, live-update failures are visible, feature-specific behavior moves out of the shared runtime, and lifecycle/HTMX/live-update/picker regressions are covered.


---
id: ir-4dtf
status: closed
deps: [ir-uu3x]
links: []
created: 2026-05-29T03:16:10Z
type: task
priority: 2
assignee: beaudan
parent: ir-kuyy
tags: [agent-loop, roster, navigation, frontend-surface]
---
# Migrate roster content staff-panel and navigation responses

Convert broader roster success responses and navigation/filter flows to the semantic invalidation model where they are mutating actor successes, while preserving direct view-state GET behavior.

## Design

Content/staff-panel mutation successes should emit actor-local semantic invalidation plus extras, not business OOB HTML. Week/group/filter navigation and pure view-state GETs may remain direct fragment/page responses when no mutation/passive invalidation is needed. URL push and live metadata must remain correct across week/group/filter changes.

## Acceptance Criteria

Roster content/staff-panel mutation success responses contain no authoritative business OOB. Pure navigation/refetch GET behavior is explicitly classified and remains correct. URL push, surface metadata, and scroll behavior are covered if changed.

## Notes

**2026-07-07T05:15:25Z**

Migrated roster content/navigation/preference success helpers to semantic actor-local invalidation. respondWithRosterFragments now delegates to a shared actor invalidation helper, and respondWithRosterContentUpdate invalidates RosterProjectionContent plus toast instead of rendering content business HTML. Layout/warning/wage preference successes now emit semantic roster grid fragment invalidations through respondWithRosterFragmentsUpdate. Fragment GETs remain plain target-node HTML and tests fetch those GET endpoints to verify rendered layout/wage content after actor responses. Verification: hspec-test --match 'RosterWeeksController'.

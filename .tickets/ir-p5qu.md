---
id: ir-p5qu
status: open
deps: [ir-o1rw]
links: []
created: 2026-07-09T03:12:56Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-sli3
tags: [agent-loop, page-help, chunk, roster]
---
# Add role-aware Roster help and wire the Roster page

Add the roster help topic and attach the title-adjacent help trigger to the Roster page.

## Design

Implement the roster topic with staff and manager/admin/owner/support-aware sections. Ground copy in Web/RosterWeeks/SPEC.md and current roster chrome. Keep descriptions succinct and task-oriented.

## Acceptance Criteria

Roster page renders Roster [?]. Roster help covers week/group navigation, create/edit where permitted, day-column drag/drop move, Ctrl copy on Windows/Linux, Option/Alt copy on macOS, layout/settings, warnings, wage estimates, assignment prevention filters, copy/sort where relevant, live/publish behavior, and staff visibility of drafts. Role filtering omits manager-only guidance for staff-only viewers. Typecheck and focused Hspec for roster help filtering pass.


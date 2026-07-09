---
id: ir-6el7
status: open
deps: []
links: []
created: 2026-07-09T02:39:01Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-z20h
tags: [agent-loop, profile, shift-preferences, ui]
---
# Improve shift preference save UX

Make shift preference editing clearer and avoid full-page reload on save.

## Design

Use existing profile FrontendSurface/profile section patterns to refresh the preferences section in-place after save. Improve explanatory copy/labels around weekday availability and whole-hour preference windows.

## Acceptance Criteria

Saving shift preferences does not cause a full page reload in the normal HTMX path. Success/error feedback is clear. Existing validation remains server-side and tamper-safe. Profile/shift preference tests pass.


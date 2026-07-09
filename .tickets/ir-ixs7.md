---
id: ir-ixs7
status: open
deps: [ir-jxle, ir-gwjb]
links: []
created: 2026-07-09T10:10:25Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-rlh2
tags: [agent-loop, time-picker, roster]
---
# Apply venue picker window and defaults to roster shift dialogs

Use the configured venue picker window for roster shift create/edit dialogs and default new roster shifts.

## Design

Thread venue picker window data into roster shift dialog render data. New roster shifts default start/end from venue config using 8h clamped duration. Existing shifts keep saved values. Start/end controls render venue-specific picker ranges, and hard-coded 06:00 to 05:45 validation/help copy is removed or made generic.

## Acceptance Criteria

New roster shift dialogs open with default start/end populated and +/- works immediately. Existing out-of-window roster shift values display and are not hard errors solely because of venue window. Roster-focused tests cover defaults and existing out-of-window rendering/validation behavior.


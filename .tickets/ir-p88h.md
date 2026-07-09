---
id: ir-p88h
status: closed
deps: [ir-jxle, ir-gwjb]
links: []
created: 2026-07-09T10:10:25Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-rlh2
tags: [agent-loop, time-picker, timesheets]
---
# Apply venue picker window and defaults to timesheet dialogs

Use the configured venue picker window for timesheet entry create/edit dialogs and default new entries.

## Design

Replace hard-coded timesheet picker ranges with venue picker window values for shift and break time fields. New timesheet entries default start/end from venue config using 8h clamped duration. Preserve existing timesheet validation for 15-minute increments, end after start, maximum 16h, and break containment.

## Acceptance Criteria

New timesheet dialogs open with default start/end populated and +/- works immediately. Timesheet picker modal options honor venue config. Existing out-of-window values display and keep disabled +/- until moved into range. Focused timesheet tests pass.


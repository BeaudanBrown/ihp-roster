---
id: ir-rlh2
status: open
deps: []
links: []
created: 2026-07-09T02:39:01Z
type: epic
priority: 2
assignee: Beaudan Brown
parent: ir-z20h
tags: [agent-loop, time-picker, admin, roster, timesheets]
---
# Configure venue time-picker window and default shift times

Allow venue admins to configure the shared roster/timesheet picker window, and use that window to provide sensible default start/end times so new roster shifts and timesheet entries can use +/- immediately.

## Design

Store venue picker start/end in `venue_config`, defaulting to the current `06:00` to `05:45` behavior. Values are quarter-hour aligned and may wrap after midnight. Treat the configured window as UI/default guidance, not as a destructive validation boundary for existing roster or timesheet records.

Roster and timesheet time-picker fields render venue-specific `data-time-picker-start` and `data-time-picker-end` values. Browser step buttons continue to operate only when the current value exists in the configured option list, so existing out-of-window values remain displayed but have disabled +/- until changed into range.

New roster shifts and new timesheet entries default to `start = venue picker start` and `end = start + 8 hours`, clamped to the configured window end when the window is shorter than 8 hours. Roster timeline selectable axis/dropzones follow the configured venue picker window.

## Acceptance Criteria

Venue admins can configure the shared time-picker window in Admin Venue Settings. Existing venues inherit `06:00` to `05:45`. New roster shift dialogs and new timesheet entry dialogs default start/end from venue config and allow +/- immediately. Roster and timesheet picker modal option ranges honor the venue setting. Existing saved times outside the venue window display without being rejected solely for being outside the window, with +/- disabled for those fields until an in-window value is selected. Roster timeline dropzones/axis use the configured picker window. Schema migration, generated types, focused Hspec, typecheck, and frontend checks pass.

## Non-goals

No per-roster-group or per-day picker window. No configurable default shift duration yet. No migration or mutation of existing saved roster/timesheet times. No payroll/pay calculation behavior changes. No broad timesheet validation change beyond picker/default inputs.

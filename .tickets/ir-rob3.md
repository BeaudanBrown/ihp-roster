---
id: ir-rob3
status: closed
deps: []
links: []
created: 2026-05-02T01:12:01Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9jap
tags: [area:roster, area:pilot, venue:rooks]
---
# Add opt-in roster end times and required shift types

## Design

Add a venue setting for roster end times. When enabled, staffed roster slots may be incomplete while drafting, but a roster week cannot go live unless every staffed shift has start time, end time, and shift type. End times are visible to all users. Overnight shifts are valid: an end time earlier than start time means the following day. Replace the roster flag/note-as-shift-type pattern with an explicit inline shift type select per staffed roster slot.

## Acceptance Criteria

Venue can opt into roster end times; staffed draft slots can remain incomplete; go-live blocks missing start/end/shift type for staffed slots; unstaffed slots do not require shift type; overnight shifts calculate a concrete next-day end datetime; roster UI uses inline shift type selection instead of the flag column.


## Notes

**2026-05-02T01:45:50Z**

2026-05-02: Foundation landed in commit f302f6d: added venue_config.roster_end_times_enabled, nullable roster_slots.end_time and roster_slots.shift_type_id, shift-type FK/index, and trigger coverage to keep roster slot shift types in the roster week venue. Existing roster UI/workflows remain unchanged. Remaining work: admin opt-in UI, inline roster end-time/shift-type editing, live-week validation that blocks publishing incomplete staffed slots, overnight duration semantics, and replacing note/flag-as-shift-type UX.

**2026-05-02T03:04:19Z**

2026-05-02: Completed opt-in roster end-time and shift-type UI slice. Added admin venue setting, inline start/end/shift-type editing when enabled, overnight duration calculation, copy/replace preservation, publish blocking for incomplete staffed slots, day-column visual support, and focused Admin/Roster controller tests. Visual checks: output/playwright/roster-day-columns-end-times.png and output/playwright/admin-venue-settings.png. Remaining payroll-dependent children cover auto-timesheets and predicted wage totals.

# Roster and Conflict Rules

## Roster lifecycle

1. Any authenticated current-venue member with a completed profile can browse roster week offsets.
2. Viewing a missing week as any authenticated current-venue member auto-creates that week in draft mode (`is_live = false`).
3. Managers, Venue Admins and Venue Owners edit assignments directly on the roster week page.
4. Managers, Venue Admins and Venue Owners control live/draft state from roster settings.
5. Staff can browse all week offsets and may cause draft week materialization, but only published/live roster content is shown.
6. When a staff user views an unpublished week, the page shows the roster shell with a "not published yet" state rather than draft assignments.

## Copy week

- Copy/import operation makes the target `week_offset` identical to the source week.
- Import overwrites any existing target roster content after an explicit confirmation.
- Imported weeks preserve the source week's structure and assignments exactly.

## Assignment filtering

Roster assignment UI must support filter toggles:

- Hide staff at ideal shifts or greater.
- Hide staff on leave.
- Hide staff with no availability preference for the roster day.
- Hide staff already assigned a shift that day.

## Sheet-style roster presentation

- Weekly roster should be representable in a print-friendly sheet format:
  - Day/date left column.
  - Repeating rows per day.
  - Three chronological blocks (`Early`, `Mid`, `Late`) with `start_time`, `staff`, and optional shift type.
- Shift types are explicit roster-slot assignments, not free-text note/flag codes.
- The roster page also provides a Manager, Venue Admin and Venue Owner staff side panel:
  - default visible
  - populated with active linked staff only
  - sorted by first name
  - each row shows name, assigned shifts in the currently viewed week, ideal shifts, user role, and an edit action

## Conflict flagging

A slot assignment can produce conflict flags. Priority order and visual severity for display:

**Critical Conflicts (Rendered as Dark Red dropdown background):**
1. Duplicate assignment conflict.
2. Leave conflict.
3. Late-to-Early conflict.

**Advisory Conflicts (Rendered as Light Pink dropdown background):**
4. Availability refusal conflict.
5. Preferred start-window conflict.
6. Ideal-shift threshold exceeded.

## Staff shift preferences

- Preferences are recurring weekly availability templates scoped to a staff member, not to a roster group.
- The current schema enforces at most one active preference row per staff member and weekday; one active preference row means the staff member is available that day.
- Each available row stores a whole-hour preferred start window from 5 AM to 11 PM (`preferred_start_hour` to `preferred_end_hour`, inclusive); if multiple same-day windows are supplied to conflict evaluation, a slot start matching any window is treated as preferred.
- Slot names such as Early/Mid/Late are roster layout labels only; they are not part of staff availability preferences.
- If a roster slot has a start time outside the preferred start window, show an advisory conflict. Slots without a start time only use the available/unavailable day signal.

## Late-to-Early rule

- Evaluate **start-to-start gap** between a staff member’s relevant consecutive shifts.
- If gap is less than `venue_config.late_to_early_min_start_gap_minutes`, flag conflict.
- This rule is evaluable from roster plan data even when explicit end times are unknown.

## Temporal invariants

- `week_offset` is based on global fixed epoch.
- `day_offset` constrained to 0..6.
- Roster calculations should be timezone-aware via `venue_config.timezone`.

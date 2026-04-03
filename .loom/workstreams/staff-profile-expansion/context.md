# Staff Profile Expansion

## Objective

Expand the venue-scoped staff profile model and editing surfaces so the app supports required personal/contact fields, preferred-name storage, recurring shift preferences per eligible roster group and `weekday x slot`, and advisory roster warnings derived from those preferences.

## Settled Product Decisions

- `users.email` remains the canonical login email and is read-only on profile pages for now.
- `staff` should store:
  - `first_name`
  - `last_name`
  - `preferred_name` optional
  - `phone` required
  - `emergency_contact_name` required
  - `emergency_contact_phone` required
  - `ideal_shifts_per_week` required with default `0` and validation range `0..7`
- Managers/admins may edit another staff member with the same effective personal-profile fields as the user themselves.
- Recurring shift preferences are weekly templates only, not date-specific overrides.
- Preferences are scoped per eligible roster group and per `weekday x slot`.
- Checkbox presence means a positive preference for that slot.
- If a given day within a roster group has zero preferred slots, treat that as a hard cannot-do-day warning only.
- Preference-derived warnings remain advisory; assignment is never blocked.
- Later hide/filter toggles on the roster should consume the same warning facts rather than inventing a second interpretation path.

## Current Code Starting Point

- Self-service profile editing currently only updates `firstName` and `lastName` on the current venue-scoped `staff` row.
- Profile completion currently means non-empty first and last name only.
- Manager staff editing already covers:
  - first name
  - last name
  - `idealShiftsPerWeek`
  - `isActive`
  - roster-group applicability
- Existing `staff_availability` is coarse day/date availability used by the conflict engine; it does not model roster-group or slot-level preferences and should not be reused as the recurring preference store.

## Required Read Order

1. `repos/ihp-roster/AGENTS.md`
2. `repos/ihp-roster/Application/AGENTS.md`
3. `repos/ihp-roster/Web/Controller/AGENTS.md`
4. `repos/ihp-roster/Web/View/AGENTS.md`
5. `repos/ihp-roster/Application/Schema.sql`
6. `repos/ihp-roster/Web/Controller/Profiles.hs`
7. `repos/ihp-roster/Web/View/Profiles/Edit.hs`
8. `repos/ihp-roster/Web/Controller/Staff.hs`
9. `repos/ihp-roster/Web/View/Staff/Edit.hs`
10. `repos/ihp-roster/Application/Helper/Controller.hs`
11. `repos/ihp-roster/Application/Helper/Conflict.hs`

## Verification Target

- `bash ./bin/in-env typecheck`
- targeted tests while iterating
- broader test selection after the main slices land


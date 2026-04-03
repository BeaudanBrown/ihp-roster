You are working on the `staff-profile-expansion` lane in `ihp-roster`.

Read, in order:

1. `AGENTS.md`
2. `Application/AGENTS.md`
3. `Web/Controller/AGENTS.md`
4. `Web/View/AGENTS.md`
5. `.loom/workstreams/staff-profile-expansion/context.md`
6. `.loom/workstreams/staff-profile-expansion/handoff.md`

Current objective:

- expand venue-scoped staff profiles with required contact data and preferred-name storage
- keep `users.email` canonical and read-only on profile pages
- make `ideal_shifts_per_week` required with a `0..7` validation contract
- add recurring per-roster-group `weekday x slot` shift preferences for eligible groups only
- unify self-service and manager-editable personal profile surfaces
- keep preference-derived roster behavior advisory only

Implementation order:

1. schema and validation foundation
2. shared self-service and manager profile-editing surface
3. recurring preference persistence and UI
4. roster warning/highlight integration
5. verification

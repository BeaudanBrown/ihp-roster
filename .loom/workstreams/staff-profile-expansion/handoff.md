# Staff Profile Expansion Handoff

## Status

- Workstream created on 2026-04-03.
- Coordinator epic: `coordinator-mux`
- Current implementation focus: `coordinator-mux.2` schema and validation foundation

## Immediate Next Steps

1. Extend `staff` in `Application/Schema.sql` with preferred-name and required contact fields.
2. Add a recurring shift-preference table keyed by staff, eligible roster group, slot name, and weekday.
3. Regenerate types and update profile-completion / validation helpers.
4. Refactor the self-service and manager edit surfaces onto a shared expanded form.

## Guardrails

- Keep `users.email` read-only on profile pages for now.
- Do not reuse `staff_availability` as the recurring slot-preference store.
- Keep roster-group applicability manager-owned and separate from self-service preference editing.
- Preference-derived roster behavior is warning/highlight only.


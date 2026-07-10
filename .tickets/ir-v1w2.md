---
id: ir-v1w2
status: closed
deps: []
links: []
created: 2026-07-10T05:32:28Z
type: bug
priority: 1
assignee: beaudan
parent: ir-zpyz
tags: [agent-loop, schema, db, hspec]
---
# Fix time picker schema check constraint style

Update time picker check constraints so SchemaSpec no longer detects IN-based CHECK constraints that pg_dump can rewrite into parser-hostile ANY(ARRAY ...) forms.

## Design

Update Application/Schema.sql constraints for time_picker_start_minute_of_day and time_picker_final_selectable_minute_of_day to parser-friendly range/modulo checks, preserving non-equality. Compare against Application/Migration/1783600000.sql and add or adjust migration only if deployed databases lack the intended upgrade path.

## Acceptance Criteria

SchemaSpec passes. regen-types passes. typecheck passes. Migration/no-migration decision is recorded in the ticket notes.


## Notes

**2026-07-10T06:38:31Z**

Verified Application/Migration/1783600000.sql already carries the deployed upgrade path for these constraints. No new migration is needed for this ticket; Schema.sql is being aligned to the existing migration semantics using parser-friendly MOD(..., 15) checks instead of IN lists or % operator. Focused Schema specs, regen-types, and typecheck pass.

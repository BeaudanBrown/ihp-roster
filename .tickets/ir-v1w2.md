---
id: ir-v1w2
status: open
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


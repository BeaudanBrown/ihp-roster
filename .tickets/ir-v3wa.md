---
id: ir-v3wa
status: open
deps: [ir-jlm2]
links: []
created: 2026-07-10T05:32:28Z
type: bug
priority: 1
assignee: beaudan
parent: ir-zpyz
tags: [agent-loop, e2e, ui, roster]
---
# Resolve remaining UI and test-contract E2E failures

Address E2E failures not resolved by surface/live contract work, deciding case by case whether product UI or test expectation is wrong.

## Design

Cover duplicate accessible roster links, admin settings card count/alignment expectation, roster staff highlight toggle persistence, roster time picker label/selected-time expectations, and hidden Double shifts checkbox flake.

## Acceptance Criteria

Focused affected specs pass: auth, header-navigation, admin-roster-ui-polish, roster-staff-highlight, roster-time-picker, and roster-assignment-filters. Full bash ./bin/in-env e2e passes.


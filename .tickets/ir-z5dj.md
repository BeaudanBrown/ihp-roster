---
id: ir-z5dj
status: open
deps: []
links: [ir-3vc6, ir-hw2v, ir-lz0x]
created: 2026-04-30T06:31:22Z
type: task
priority: 2
assignee: beaudan
parent: ir-m8hc
tags: [area:docs, area:payroll, source:2026-04-30-audit]
---
# Update payroll specs and agent docs to the award-level model

Remove or explicitly supersede stale pay_levels/pay_level_day_rules guidance and document the current award_levels, staff.default_award_level_id, shift_types.override_award_level_id, base-rate, and penalty-rate model.

## Design

Update specs/02-domain-model.md, specs/06-pay-engine.md, Application/AGENTS.md, and any active plan text that still presents pay_level_day_rules as current. If day-specific overrides are deferred rather than removed, state that explicitly as future work instead of current behavior.

## Acceptance Criteria

Docs no longer describe nonexistent pay_level_day_rules as current schema; pay level resolution text matches Application/Schema.sql; snapshot limitations and planned hardening are cross-referenced to the pay reproducibility ticket.

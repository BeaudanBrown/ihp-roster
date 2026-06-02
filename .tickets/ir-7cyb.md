---
id: ir-7cyb
status: open
deps: []
links: []
created: 2026-06-02T07:20:13Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:xero, area:providers, analysis]
---
# Remeasure Xero baseline and active-ticket overlap for provider migration

Audit current Xero code, schema, docs, and open tk tickets so the provider migration starts from implemented behavior rather than stale plan text.

## Design

Compare Application/Xero, Application/Helper/Xero*, Web/Controller/Admin/Xero, Web/View/Admin/Xero, Application/Schema.sql, Application/Xero/SPEC.md, docs/workstreams/xero-payroll.md, and open Xero tickets. Identify which existing Xero tickets should be closed, superseded, linked, or kept independent when the provider-neutral epic starts.

## Acceptance Criteria

A note or doc update records the current Xero baseline, active-ticket overlap, migration risks, and recommended ticket routing. The new provider epic is linked to relevant Xero epics/tickets, and no Xero behavior is intentionally dropped from the migration scope.


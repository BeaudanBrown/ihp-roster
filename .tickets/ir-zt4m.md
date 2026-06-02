---
id: ir-zt4m
status: open
deps: [ir-wkpb]
links: []
created: 2026-06-02T07:20:13Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:myob, area:providers, research]
---
# Probe MYOB direct API access credential and payroll endpoint behavior

Use assumed paid MYOB developer access to validate the direct API flow and resolve company-file credential requirements before committing to storage behavior.

## Design

Probe OAuth with prompt=consent, businessId/cf_uri capture, token exchange/refresh lifetimes, headers, OData paging, company-file validation, cftoken requirements, and payroll endpoints for employees, employee payroll details, wage categories, accounts, and timesheets. Determine whether cftoken can be prompt-per-operation/session-only or must be stored encrypted for complete feature parity. Confirm payroll-enabled sandbox access and any paid-tier limitations.

## Acceptance Criteria

A durable note or docs update records exact endpoints tested, scopes used, header requirements, token lifetimes, cftoken decision criteria, sandbox limitations, and implementation recommendations. If access/cost/API limits block feature parity, follow-up tickets are created or this epic is re-scoped before MYOB implementation proceeds.


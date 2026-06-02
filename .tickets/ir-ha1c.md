---
id: ir-ha1c
status: open
deps: [ir-wkpb, ir-7cyb]
links: []
created: 2026-06-02T07:20:13Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:providers, architecture]
---
# Define payroll provider contract and capability model

Design the provider-neutral Haskell contract that downstream Payroll flows will consume for Xero, MYOB, and future providers.

## Design

Define provider identity, capability flags, auth lifecycle, reference sync operations, staff/pay-item mapping model, period/pay-run abstraction, readiness/blocker shape, preview input/output types, submission command/result shape, and correction/update hooks. Account for provider-specific concepts such as Xero pay runs/payroll calendars and MYOB timesheet PUT/Processed entries without leaking them into generic UI flows.

## Acceptance Criteria

Provider contract types and design notes are in place with tests or compile-time examples showing Xero and MYOB can express their capabilities. The design explicitly covers unsupported capabilities, user-facing labels, provider diagnostics, and how downstream flows branch on capabilities rather than provider names.


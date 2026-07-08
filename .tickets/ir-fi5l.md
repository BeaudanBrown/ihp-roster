---
id: ir-fi5l
status: open
deps: [ir-9yr7, ir-qy7c]
links: []
created: 2026-07-08T09:28:50Z
type: bug
priority: 1
assignee: Beaudan Brown
parent: ir-2nrg
tags: [area:exports, area:xero, area:payroll, agent-loop]
---
# Align exports and Xero pay-item effective keys

Ensure payroll exports and Xero pay-item buckets/preview use the same venue-effective award-rate dates as pay calculation.

## Design

Keep exports driven by canonical pay results where possible. Update Xero local earnings buckets, preview, and managed pay item effective-date keys/names to use Bepis venue-effective dates rather than raw FWC dates. Imported Xero pay items are unchanged.

## Acceptance Criteria

Xero bucket key/name uses the rollover week-start date for a mid-week FWC change; no duplicate old/new current bucket is generated for one worked date; payroll export parity remains consistent with canonical pay results.


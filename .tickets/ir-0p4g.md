---
id: ir-0p4g
status: open
deps: [ir-f7wo, ir-zt4m]
links: []
created: 2026-06-02T07:20:13Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:myob, area:providers, api-client]
---
# Implement MYOB direct API client foundation

Add the MYOB provider adapter client for OAuth, authenticated requests, paging, error handling, and typed request/response boundaries.

## Design

Implement config reading, authorization URL builder, token exchange, refresh, request headers, optional cftoken injection hook, JSON encoding/decoding, OData-style pagination with NextPageLink, structured HTTP/decode/semantic errors, and test overrides like the existing Xero client.

## Acceptance Criteria

MYOB client tests cover OAuth request construction, refresh rotation, required headers, cftoken hook behavior, pagination, representative success/error responses, and no token/credential logging. No downstream Payroll flow calls MYOB HTTP directly.


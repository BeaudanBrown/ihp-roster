---
id: ir-yikx
status: open
deps: [ir-tsvi]
links: []
created: 2026-04-30T03:05:46Z
type: task
priority: 1
assignee: beaudan
parent: ir-ujwc
---
# Cover Xero submission with strict contract mock tests

Use the vendored OpenAPI-backed contract/mock harness to test concrete create submission behavior: POST /Timesheets array envelope, required headers including Idempotency-Key, successful per-employee persistence, semantic Xero error persistence, transport failure persistence, duplicate remote timesheet blocking, and deterministic retry/idempotency behavior.


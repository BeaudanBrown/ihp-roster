---
id: ir-yikx
status: closed
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


## Notes

**2026-04-30T04:06:05Z**

Starting strict submission coverage and retry/idempotency slice. Current committed tests cover strict success and duplicate blocking; adding configurable strict mock responses, semantic/transport/partial-failure coverage, and a retry service that reuses the persisted submission row/key.

**2026-04-30T04:10:08Z**

Implemented strict submission coverage for semantic Xero errors, transport failures, partial failures, duplicate blocking, singleton array create requests, idempotency-key length, and retry idempotency reuse. Added retryXeroDraftTimesheetSubmission to reuse the persisted submission row/request/idempotency key. Verified with typecheck and hspec-test --match Xero --match Schema. Full lint still reports pre-existing Xero helper eta-reduction hints outside this slice.

---
id: ir-mr3v
status: closed
deps: [ir-pedb]
links: []
created: 2026-04-30T00:39:49Z
type: task
priority: 2
assignee: beaudan
parent: ir-176p
tags: [area:xero, testing, api]
---
# Generate strict local Xero mock endpoints from the vendored contract

Add a local strict mock harness for Xero HTTP integration tests after the OpenAPI contract is vendored, using the spec as the source of endpoint truth.

## Design

Follow `docs/archive/plans/64-xero-openapi-contract-and-probes.md`.

Use the vendored OpenAPI spec to define expected method/path/header/body envelopes for local WAI/Warp test handlers or another lightweight Hspec harness. The mock should reject unexpected paths, missing required headers, and wrong body container shapes. Fixtures may use redacted Demo Company responses or OpenAPI examples, but the mock must remain a verifier of local request rendering rather than a hand-written model of Xero business behavior.

## Acceptance Criteria

Tests can exercise the concrete HTTP transport against localhost without real Xero credentials; unexpected path/header/body drift fails fast; fixtures are redacted and committed only when they contain no token/customer material.

## Progress

- Added the first OpenAPI-powered verifier layer in `Test/XeroContractSpec.hs`: every current app-side Xero request builder is validated against the vendored operation table for server, method, path, required headers, query/header params, and request body envelope shape.
- Added a strict localhost Warp mock in `Test/XeroContractSpec.hs` that validates incoming concrete HTTP requests against the vendored OpenAPI-backed contract table, rejects unexpected endpoints or malformed requests, and returns small redacted fixtures.
- Added `withXeroRequestBaseUrlsForTest` in `Application.Helper.Xero` so tests can route the preserved `XeroClient` HTTP boundary to localhost without changing production defaults.
- Verified with `bash ./bin/in-env typecheck` and `bash ./bin/in-env hspec-test --match "Xero contract"`.

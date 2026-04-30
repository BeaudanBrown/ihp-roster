---
id: ir-pedb
status: closed
deps: []
links: []
created: 2026-04-30T00:39:38Z
type: feature
priority: 1
assignee: beaudan
parent: ir-176p
tags: [area:xero, api, testing, agent-contract]
---
# Vendor Xero OpenAPI specs and contract-test request construction

Bring Xero's official OpenAPI specs into the repo as a pinned, offline, agent-readable contract and add tests that verify local Xero request construction against the spec.

## Design

Follow `plans/64-xero-openapi-contract-and-probes.md`.

Add vendor/xero-openapi with xero-payroll-au.yaml and xero-identity.yaml plus a manifest recording upstream repo, release/commit, source URLs, and fetched date. Add a small update script that refreshes those files from XeroAPI/Xero-OpenAPI and fails clearly if downloaded content is missing required paths. Refactor low-level Xero request construction only as much as needed to expose method, URL/path, query params, headers, and body shape without performing HTTP. Add Hspec contract tests for token refresh/exchange, connections, Payroll AU employees, PayItems, payroll calendars, and Timesheets list/show/create/update. Tests should compare against vendored OpenAPI server URLs, paths, methods, required headers, idempotency requirements, and array-vs-object body shape.

## Acceptance Criteria

Vendored OpenAPI files are committed with a manifest; agents can inspect the local specs without network access; request-construction tests fail if the app drifts from Xero's documented endpoint paths/methods/headers/body shape; bash ./bin/in-env typecheck and the focused Hspec spec pass.

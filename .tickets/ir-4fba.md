---
id: ir-4fba
status: open
deps: [ir-pedb]
links: []
created: 2026-04-30T00:39:44Z
type: task
priority: 1
assignee: beaudan
parent: ir-176p
tags: [area:xero, tooling, agent-safety]
---
# Harden Xero live probe scripts for agent-safe diagnostics

Tighten the existing Xero probe workflow so agents can collect real Xero status/error responses only through explicit, auditable, tenant-scoped operations.

## Design

Follow `docs/archive/plans/64-xero-openapi-contract-and-probes.md`.

Keep xero-pay-item-probe read-only by default. Make every real network mode obvious in --help. Require a tenant allowlist environment variable before any mutating POST, e.g. XERO_ALLOW_MUTATION_TENANT_ID matching the connection tenant id, in addition to --confirm-post. Add redacted request/response artifact output under output/xero-probes/ with timestamp, tenant id/name, method, URL path, request body, status, and response body, excluding Authorization and token material. Consider --no-refresh or --prefer-stored-access-token for read-only diagnostics when a non-expired encrypted access token exists, while preserving the current refresh path for normal live validation. Document that refresh rotates tokens and may invalidate build/dev-xero-connection.sql.

## Acceptance Criteria

Agents cannot POST to Xero with only --confirm-post; mutation requires explicit tenant allowlist; probe output never prints auth headers or token material; each real Xero call writes a redacted artifact; AGENTS.md documents the safe read-only and mutation workflows.

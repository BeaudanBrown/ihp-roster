---
id: ir-6kzl
status: closed
deps: []
links: []
created: 2026-07-01T01:40:01Z
type: epic
priority: 2
assignee: beaudan
tags: [agent-loop, frontend, contracts, typescript, haskell]
---
# Solidify generic Haskell-to-TypeScript frontend contracts

Refactor the frontend/backend browser contract system so shared Haskell/TypeScript concepts are defined as narrow Haskell DTOs/enums with generic generated codecs. The same source generates Haskell JSON encode/decode, TypeScript types, guards, parse helpers, encode helpers, and typed constants. Remove all stale/manual/legacy/bridge generation paths and guard against reintroduction.

## Design

Use Haskell frontend DTO types as the source of truth for the browser seam only. Keep FrontendSchema as the central IR and TypeScript renderer. Add generic FrontendCodec derivation for records, closed enums, tagged unions, references, arrays, optional/nullable fields, and JSON-shaped DTOs. Wire JSON shapes may change freely to generator-friendly forms. Generate type/is/parse/encode helpers for TypeScript; encode helpers are identity for JSON-shaped DTOs and remain generator-owned. Constants and registries remain values but are encoded through generated DTO codecs. Prefer generic registry container types such as Partial<Record<LiveSurfaceFamily, LiveSurfaceManifestEntry>> over current-value-keyed object types where appropriate. Leave a future HIE/GHC API path open by centering all output on DTO types plus FrontendSchema.

## Acceptance Criteria

Every Haskell-owned frontend contract uses generic DTO codecs or has an explicitly justified generator-level exception. Generated TypeScript includes type, guard, parse helper, and encode helper for each generated codec. Haskell JSON encode/decode and generated TypeScript shape come from the same codec source. No production frontend contract module handwrites TypeScript declarations, validators, parsers, encoders, raw schema field lists for DTOs, legacy/manual/spike/bridge contract modules, stale aliases, or migration allowlists. Adding a new frontend DTO enum/union in Haskell changes generated TS and TypeScript exhaustive handling fails when not updated. Frontend runtime imports generated contracts only. Docs describe the final system and adding new live surfaces/intents/contracts. Verification: typecheck, frontend-contracts-check, frontend-check, focused Frontend contract Hspec, focused LiveSurface/Interaction/LiveUpdate Hspec as touched, and doc-drift-check when docs change.


## Notes

**2026-07-01T01:41:02Z**

Planning workstream added at docs/workstreams/generic-frontend-contracts.md. Implementation should keep durable final behavior in local frontend/live-update/interaction docs and use this workstream only for future/active plan context.

**2026-07-01T02:33:34Z**

Completed all child tickets for the generic Haskell-to-TypeScript frontend contract epic. Final state: generic DTO foundation, app/UI/roster/live-update/interaction/live-surface DTO migrations, generated parse/encode helpers, exhaustive generated-union switch guard, final lockdown guardrails, and durable docs. Final verification run covered: typecheck; frontend-contracts-check; frontend-check; doc-drift-check; hspec-test --match 'Frontend contract'; hspec-test --match 'LiveUpdate'; hspec-test --match 'LiveSurface' (rerun after guard allowlist fix); hspec-test --match 'interaction surface'.

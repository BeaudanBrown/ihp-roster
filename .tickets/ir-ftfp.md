---
id: ir-ftfp
status: open
deps: []
links: []
created: 2026-06-25T11:57:29Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-vpmd
tags: [agent-loop, frontend, contracts, haskell, typescript, spike]
---
# Spike aeson-typescript for frontend wire contracts

Prove aeson-typescript fits this IHP/Nix project and our desired generated wire-contract shapes before broad migration.

## Design

Add aeson-typescript to the project Haskell package set. Build a small representative contract prototype covering a plain enum, a discriminated union with tag/type field, a record with optional/null fields, UUID-as-string/newtype handling, and a nested wire message. Compare generated TypeScript against the current frontend needs and document selected Aeson Options/encoding conventions. Wire protocol changes are acceptable if generated Haskell JSON and TypeScript stay aligned.

## Acceptance Criteria

Project typecheck can import aeson-typescript; frontend-contracts can generate a representative snippet; chosen encoding conventions are documented in the ticket notes or code comments; risks/limitations are recorded before migration tickets depend on it.


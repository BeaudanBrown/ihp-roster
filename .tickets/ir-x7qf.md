---
id: ir-x7qf
status: closed
deps: []
links: []
created: 2026-07-01T01:40:01Z
type: feature
priority: 2
assignee: beaudan
parent: ir-6kzl
tags: [agent-loop, frontend, contracts, haskell]
---
# Add generic frontend codec derivation foundation

Implement reusable generic codec machinery for the frontend/browser seam while preserving the existing FrontendSchema renderer and current contracts during migration.

## Design

Add modules such as Application.Helper.Frontend.Generic and Application.Helper.Frontend.Options. Support generic records, closed string enums, tagged unions, named references, arrays, optional and nullable fields, project default naming options, local overrides, and JSON-shaped identity TypeScript encoders. Extend the TypeScript renderer to emit parseX(value: unknown): X and encodeX(value: X): X alongside type and isX guard. Existing manual codecs continue to render during migration.

## Acceptance Criteria

Representative generic-derived record, enum, and tagged union generate matching Haskell JSON encode/decode, FrontendSchema, TypeScript type, guard, parse helper, and encode helper. Invalid unknown input is rejected by generated parse helpers. Encode helpers are generated and typecheck as identity for JSON-shaped DTOs. Existing frontend-contracts-check and focused Frontend contract tests pass.


## Notes

**2026-07-01T01:53:46Z**

Implemented generic frontend codec foundation with Generic/Options modules, generated parse/encode TS helpers, representative generic Hspec coverage, and frontend runtime parse/encode tests. Verification: typecheck; frontend-contracts-check; frontend-check; hspec-test --match 'Frontend contract'.

---
id: ir-4h3p
status: open
deps: []
links: []
created: 2026-07-05T10:20:36Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-815h
tags: [frontend-contracts, hardening, constants]
---
# Tighten FrontendContract Haskell value accessors

Make AppValues/RosterValues safer and less drift-prone.

## Design

Review Application.Helper.FrontendContract.Values. Replace the local ad-hoc nameToKebab with the canonical naming helper used by reflection/rendering. Add total lookup helpers returning Either/Text diagnostics alongside the existing convenience accessors, and add Hspec coverage that every AppValues/RosterValues exported value resolves from registeredFrontendContractIR. Decide whether a lightweight KnownFrontendValue typeclass is worth adding now; otherwise keep the runtime lookup but make failures deterministic and tested.

## Acceptance Criteria

No duplicated naming algorithm remains in Values. Missing marker/kind failures have clear diagnostics. Tests cover domIdValue, eventNameValue, enumLiteralValue, and AppValues/RosterValues exports.


---
id: ir-7huc
status: closed
deps: []
links: []
created: 2026-07-03T04:16:45Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [agent-loop, surfaces, live-updates]
---
# Unify live transport under generated FrontendSurface contracts

## Design

Replace legacy/live-surface transport and handwritten FrontendSurface subscription mapping with a single generated, type-level FrontendSurface transport model. Add Live as a fragment option, generate live subscription contracts from Scope plus live Fragment declarations, emit ready-to-use subscription metadata from Haskell mount config, replace feature-specific LiveUpdateScope/LiveFragmentKey transport with surface-native generated transport, delete legacy data-live-update-surface/LiveSurfaceManifest/registry compatibility paths, and consolidate the FrontendSurface DSL before more app work. Server-rendered HTML remains authoritative and existing user-visible live-update behavior must be preserved.

## Acceptance Criteria

No production/browser code hard-codes app-specific surface/fragment/scope mappings. No production data-live-update-surface support remains. All migrated production live behavior works via generated FrontendSurface transport. Composition-only parents require no runtime special-case. Generated TS includes surface-native live subscription types/guards. Haskell live bus uses surface-native scope keys/fragments. Docs describe the final primitive set and authoring model. Guardrails prevent reintroducing legacy live surface authoring/transport. Verification passes: frontend-contracts-check, frontend-surface-guardrails, frontend-check, typecheck, and focused Hspec for FrontendSurface, LiveUpdate, LiveSurfaceRegistry/replacement, Admin, Roster, Timesheets.


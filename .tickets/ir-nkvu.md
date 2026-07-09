---
id: ir-nkvu
status: open
deps: [ir-e41r]
links: []
created: 2026-07-09T01:05:25Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-3irv
tags: [agent-loop, frontend-surface, htmx]
---
# Standardize FrontendSurface fragment response modes

Cleanly model plain vs OOB fragment delivery without paired renderers drifting.

## Design

Introduce or standardize a small response mode API, e.g. PlainFragment and OobFragment OobSwapAttr. Plain fragment GET/refetch returns the target node itself. OOB mode remains explicit for legacy pagination/navigation seams, extras, and validation-local/direct responses where appropriate. Do not make successful migrated business refreshes actor OOB.

## Acceptance Criteria

At least one existing plain/OOB renderer pair is collapsed. Tests cover plain and OOB output for the same fragment. Fragment GET endpoints still return plain target nodes by default. Docs clarify response modes and OOB boundaries.


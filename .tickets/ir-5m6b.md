---
id: ir-5m6b
status: closed
deps: [ir-ez90]
links: []
created: 2026-05-29T03:16:11Z
type: task
priority: 3
assignee: beaudan
parent: ir-78cn
tags: [agent-loop, tests, guardrails, frontend-surface]
---
# Add guardrail tests for FrontendSurface actor invalidation conventions

Add or update tests that prevent regression to authoritative business OOB success responses on migrated `FrontendSurface` surfaces.

## Design

Extend existing strict API/MutationBoundary/LiveSurface/Surface guard specs to catch raw successful actor business OOB helpers, feature-specific actor refresh payload JSON, page live fragments, and direct successful hx-target outerHTML forms where actor-local semantic invalidation should be used. Guardrails must allow validation-local direct fragments, extras-only OOB, plain fragment GET endpoints, and documented non-FrontendSurface exceptions.

## Acceptance Criteria

Guardrail tests fail on representative obsolete success-response business OOB patterns and pass on the migrated codebase. Allowed exceptions are explicit in test names or fixtures.

## Notes

**2026-07-07T05:20:51Z**

Added SurfaceGuard coverage for migrated actor success paths. New guardrail scans Web sources and fails if obsolete actor business-OOB compatibility helper names return, including profile leave OOB responder, Xero current-section OOB renderer, roster patch/row OOB responders, and old feature-specific actor refresh payload builders. Allowed OOB exceptions remain documented in test inventory/notes. Verification: hspec-test --match 'keeps migrated actor success paths off business OOB compatibility helpers'.

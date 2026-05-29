---
id: ir-6q3e
status: closed
deps: []
links: []
created: 2026-05-29T03:16:06Z
type: epic
priority: 1
assignee: beaudan
parent: ir-cfcr
tags: [agent-loop, live-fragments, foundation]
---
# Build shared typed-fragment actor response foundation

Extract the reusable pieces learned from the timesheets refactor before migrating more pages.

## Design

Introduce shared render-mode/OOB helpers and a typed response helper that feature code can call instead of bespoke renderXxxOob and renderMainFragmentOob branches.

## Acceptance Criteria

There is a documented shared helper/API for rendering typed surface fragments as plain or OOB; timesheets uses it or has a deliberate short-term note; tests cover containment normalization and actor OOB rendering through the helper.


## Notes

**2026-05-29T04:05:17Z**

Epic complete: research note recorded the immediate-OOB helper API; Application.Helper.LiveSurface now exposes FragmentRenderMode, typed containment normalization, snapshot-based rendering, and respondWithTypedLiveSurfaceFragments; LiveSurfaceSpec covers typed normalization and actor OOB rendering with extras; timesheets consumes the shared helper without reintroducing a page/shell fragment; docs/agent guidance describe one-fragment-model/multiple-triggers and validation-failure exceptions. Verification is blocked by unrelated generated-type drift (missing XeroAccount, XeroImportedPayItem, UserFeedbackItem) and e2e cannot start without the local postgres/dev environment.

---
id: ir-jlm2
status: open
deps: [ir-zel6, ir-59zh]
links: []
created: 2026-07-10T05:32:28Z
type: bug
priority: 1
assignee: beaudan
parent: ir-zpyz
tags: [agent-loop, e2e, frontend-surface, live-updates, roster]
---
# Stabilize E2E failures caused by surface live runtime contract drift

After the FrontendSurface contract and raw-string guard fixes, rerun and fix E2E failures around generated surface attrs, live fragments, and roster pointer refs.

## Design

Focus on admin shift type live fragment metadata, profile/timesheet/leave surface config attrs, roster pointer generated source/dropzone refs, live fragment multi-view propagation, and roster duplicate conflict refreshes. Keep browser runtime generic; do not add feature-specific JS adapters for behavior that belongs in FrontendSurface/live-update runtime.

## Acceptance Criteria

Focused failing live/surface E2E specs pass. Full e2e failure count is reduced to only unrelated UI/test-contract failures if any. No feature-specific live/interaction runtime adapter is introduced.


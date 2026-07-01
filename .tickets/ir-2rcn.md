---
id: ir-2rcn
status: open
deps: [ir-kl24, ir-at5f]
links: []
created: 2026-07-01T02:44:57Z
type: task
priority: 2
assignee: beaudan
parent: ir-ao41
tags: [agent-loop, roster, frontend, interaction, e2e]
---
# Wire roster drag/drop to declared session effects

Complete the roster day-row drag/drop integration using server-declared generic effects and remove old hardcoded preview behavior.

## Design

Ensure Web.RosterWeeks.LiveSurface declares clone-shadow and dropzone-highlight effects through the Haskell interaction schema. Remove or replace the current hardcoded renderDropPreview path in the pointer runtime. Add/adjust generic CSS in the appropriate app stylesheet. Verify the existing row-grid drag/drop still submits move-roster-shift-to-slot through the generated form and that live-fragment conflict handling still clears/defer/refetches correctly.

## Acceptance Criteria

Roster day-row drag/drop uses generated effect config with no hardcoded roster session/layer names in TypeScript. Drag shadow and dropzone highlight work visually in the browser. Server-owned roster DOM remains unchanged until HTMX response. Existing move intent fields and controller behavior are unchanged. Focused frontend tests, hspec-test --match 'RosterWeeks' or focused interaction controller coverage, and a focused Playwright/E2E drag/drop preview test pass.


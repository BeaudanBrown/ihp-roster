---
id: ir-2rcn
status: closed
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


## Notes

**2026-07-01T03:07:38Z**

Roster integration uses generated effect config, removes hardcoded text preview, regenerates static JS, adds CSS and focused E2E. Verification: frontend-contracts-check; typecheck; hspec-test --match 'Frontend contract'; hspec-test --match 'interaction surface'; frontend-check; hspec-test --match 'RosterWeeks'; e2e e2e/roster-pointer-effects.spec.ts; doc-drift-check; style-audit.

**2026-07-01T03:12:26Z**

Follow-up visual correction after manual review: clone shadow now materializes direct child layout instead of relying on roster subgrid outside the grid, opacity increased to 0.96, and dropzone highlight CSS made visible with stronger background/box-shadow and plus overlay. E2E now asserts shadow text matches source text, opacity, and highlight box-shadow. Verification: frontend-test; style-audit; frontend-build; frontend-check; e2e e2e/roster-pointer-effects.spec.ts.

**2026-07-01T03:17:58Z**

Follow-up visual correction: shadow now copies the nearest computed background/color and has a default surface background; roster palette descendants inside the shadow get a soft palette background and palette border so the dragged shift no longer appears transparent/unstyled. E2E now asserts non-transparent shadow background. Verification: frontend-test; style-audit; frontend-build; e2e e2e/roster-pointer-effects.spec.ts; frontend-check.

**2026-07-01T03:25:37Z**

Follow-up behavior change per product feedback: clone-shadow now renders a generic same-size inert proxy rectangle rather than cloning/reconstructing source DOM. Proxy uses configured layer/class, source dimensions/grab offset, pastel blue background, outline, opacity 0.9, and no text/content. Updated docs/tests/E2E accordingly. Verification: frontend-test; style-audit; frontend-build; frontend-check; e2e e2e/roster-pointer-effects.spec.ts; doc-drift-check.

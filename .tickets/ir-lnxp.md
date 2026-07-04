---
id: ir-lnxp
status: closed
deps: []
links: []
created: 2026-07-04T04:34:06Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, surfaces, interaction, cleanup]
---
# Remove final FrontendSurface cleanup seams

Finish the last known live/interaction surface cleanup seams after the generated FrontendSurface interaction migration. Remove Billing's legacy data-live-update-url override, delete stale semantic InteractionDom contract fields, move roster's handwritten interaction shell/form/layer rendering into generic FrontendSurface runtime helpers, polish stale naming/docs, and lock guardrails against regressions.

## Design

Reuse existing FrontendSurface concepts rather than adding new ones. Billing checkout-return state belongs in Billing MountState, not scope and not DOM override attrs. Generated contracts may break; delete old semantic marker fields instead of preserving compatibility. Generic interaction shell/layer/form/conflict-policy rendering should replace roster-specific boilerplate in the same implementation slice, leaving no transitional wrapper. Keep DOM-owned HTMX forms as the mutation transport and keep TypeScript generic.

## Acceptance Criteria

No production data-live-update-url support remains. Generated InteractionDom no longer exposes deleted semantic marker attrs/values. Roster interaction shell/layers/forms/conflict policies are rendered by generic FrontendSurface helpers, not feature-local boilerplate. Low-risk stale LiveSurface naming/docs are cleaned or archived. Guardrails forbid reintroducing the removed seams. Verification passes: frontend-contracts, frontend-check, typecheck, hspec-test, and focused roster pointer e2e if DOM behavior changes.


## Notes

**2026-07-04T05:05:23Z**

Final verification passed: frontend-check, typecheck, hspec-test, doc-drift-check, and e2e/roster-pointer-effects.spec.ts. Guardrails now cover data-live-update-url, stale semantic InteractionDom attrs, and roster-specific interaction shell rendering.

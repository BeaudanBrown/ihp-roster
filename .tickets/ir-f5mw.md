---
id: ir-f5mw
status: closed
deps: [ir-fnfn]
links: []
created: 2026-05-29T00:51:30Z
type: task
priority: 2
assignee: beaudan
parent: ir-cqg3
tags: [agent-loop, css, tokens, palette, roster, admin]
---
# Centralize shift-type palette and feature-scoped token ownership

Remove duplicated hardcoded shift-type palette definitions and clarify which tokens are app-wide versus feature-scoped.

## Design

Introduce a shared palette module, e.g. static/css/components/palette.css, or another documented token-adjacent module. Move the palette-1 through palette-10 RGB values and soft alpha variants out of roster/admin rules into named CSS variables. Reuse those variables from admin shift-colour select and roster shift colour highlighting. Where possible, define [data-roster-shift-colour=palette-N] -> --roster-shift-type-colour once instead of duplicating it for roster cards and grid descendants. Keep schema/Application.Helper.ShiftTypeColours unchanged unless documentation needs a reference. Decide which existing tokens in static/css/tokens.css are truly app-wide and which should move into feature module roots (e.g. roster-specific row/header colours in roster tokens/module scope, timesheet card/timeline colours in timesheet module scope), preserving var names or adding compatibility aliases as needed.

## Acceptance Criteria

No raw palette rgb/rgba definitions remain duplicated in both admin and roster CSS. style-audit/css-inventory reports no unexpected hardcoded palette colors outside token/palette files. Admin shift type colour select and roster shift highlights still render palette choices. Roster conflict/tone colors remain semantic and documented. Relevant focused checks pass: style-audit, typecheck if HSX/classes changed, styling regression and roster mobile e2e if visual selectors changed.


## Notes

**2026-05-29T01:34:18Z**

Centralized persisted roster shift-type palette values in static/css/palette.css, linked it after tokens, reused palette vars in admin select and roster highlights, and removed duplicated raw palette rgb/rgba definitions/mappings from admin and roster modules. Verification: bash ./bin/in-env ./bin/style-audit passed with only non-palette warning-only colour findings remaining; bash ./bin/in-env ./bin/css-inventory passed and reports no hardcoded palette colours outside token/palette/bridge modules; bash ./bin/in-env e2e e2e/roster-mobile.spec.ts passed (27/27). Attempted bash ./bin/in-env e2e e2e/styling-regression.spec.ts; same 5 stale assertions failed as previous tickets after palette stylesheet assertion was added. Artifacts: .devenv/e2e/1780018291-714310-30182.

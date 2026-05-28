---
id: ir-1phu
status: open
deps: []
links: [ir-6vvh]
created: 2026-05-28T05:35:32Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [area:copy, area:branding, agent-loop]
---
# Bepis branding audit for customer-facing IHP strings

Audit remaining IHP/ihp-roster strings and replace only customer-facing product copy with Bepis.

## Design

Initial scan notes from 2026-05-28:
- Framework references/imports/docs such as IHP modules, IHP guide links, IHPSchema handling, and specs about implementation architecture should remain IHP.
- Infrastructure names such as Config/nix/modules/ihp-roster.nix, services.ihpRoster options, secret file paths, temp directory prefixes, and archived plan paths look internal/ops-facing and should not be renamed without a separate ops migration decision.
- Customer-facing app copy should say Bepis. Known candidate: Xero draft-timesheet copy currently says approved IHP timesheets.
- Some historical docs/archive references intentionally mention ihp-roster/IHP and should remain historical unless they leak into customer UI.

Implementation steps:
1. Re-run a targeted rg scan for IHP/ihp-roster strings before implementation.
2. Classify each occurrence as framework/internal/ops/historical/customer-facing.
3. Replace customer-facing product copy with Bepis and update test assertions.
4. Add a short note to the nearest docs/spec if a reusable copy rule emerges.

## Acceptance Criteria

All customer-facing product strings found in the scan use Bepis; framework, infrastructure, and historical IHP/ihp-roster references are intentionally left alone or separately ticketed; tests/docs are updated where visible copy changes.


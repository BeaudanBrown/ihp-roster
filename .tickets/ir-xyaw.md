---
id: ir-xyaw
status: closed
deps: []
links: []
created: 2026-05-28T05:42:05Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-1phu
tags: [area:copy, area:branding, agent-loop]
---
# Classify remaining IHP and ihp-roster strings

Produce an implementation-ready classification of remaining product-name strings.

## Design

Run a targeted rg scan for IHP, ihp, ihp-roster, and IHP Roster strings across app code, static assets, tests, specs, docs, and Nix config. Classify each actionable occurrence as framework reference, internal infrastructure/ops name, historical/archive context, or customer-facing product copy.

## Acceptance Criteria

A ticket note records the scan command and classification summary; customer-facing replacements are identified; internal/framework/historical strings are explicitly left alone or split into separate ops/docs tickets if needed.


## Notes

**2026-05-28T07:58:13Z**

Scan command used: rg -n "ihp-roster|IHP Roster|IHP-Roster|ihp roster|IHP roster|\bIHP\b|ihp" Web Application static specs docs Test e2e Config package.json README.md App.cabal Makefile, followed by a targeted Xero/export visible-copy scan. Classification: (1) framework/technical references to keep as IHP: Haskell imports from IHP.*, IHP guide links and agent docs, IHP parser/schema comments, IHP session keys, IHP auto-refresh test assertions, static vendor README references to the pinned IHP checkout, implementation specs/docs that explicitly describe framework architecture; (2) internal infrastructure/ops names to keep: Config/nix/modules/ihp-roster.nix, services.ihpRoster, ihp_roster database role/GUC, /run/secrets/ihp-roster-* paths, e2e temp directory prefix ihp-roster-export-, passkey localStorage prefix ihpRoster.*, production config names; (3) historical/archive docs to keep: docs/archive/plans/* IHP/ihp-roster wording; (4) customer-facing replacements for ir-5wct: Application/Helper/Export/Payloads.hs CSV description "IHP entries:" should say "Bepis entries:". Xero draft-timesheet UI already uses "approved Bepis timesheets" and has a regression assertion against "approved IHP timesheets". docs/workstreams/xero-payroll.md line about approved reproducible IHP payroll data is living/future product wording and should say Bepis payroll data if edited in the copy ticket. No ops migration ticket needed from this scan.

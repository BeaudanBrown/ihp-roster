---
id: ir-xyaw
status: open
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


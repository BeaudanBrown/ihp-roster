---
id: ir-z8l8
status: closed
deps: [ir-z51k, ir-qksy, ir-c6cu, ir-36t6, ir-l4ux]
links: []
created: 2026-04-30T06:30:37Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-5rhn
tags: [area:docs, area:tests, area:security]
---
# Raise input security standards in agent docs and tests

Update AGENTS.md and subdirectory agent guidance so future work consistently handles user input, request parsing, QueryBuilder/raw SQL, URL construction, CSV exports, and test coverage to the stronger standard from the security audit.

## Design

Document concise, actionable rules in AGENTS.md, Web/Controller/AGENTS.md, Web/View/AGENTS.md, Application/AGENTS.md, and Test/AGENTS.md. Add or update test guidance requiring missing/malformed/oversized/cross-venue/suspicious-payload coverage for new controllers and changed input boundaries.

## Acceptance Criteria

Agent docs call out fill missing-param behavior, safe ID parsing, server-side required validation, encoded query helpers, CSV formula injection, raw SQL restrictions, and required regression test categories. Documentation is verified against local IHP docs/source.

## Notes

**2026-04-30T07:54:33Z**

Updated root, controller, view, application, and test AGENTS.md guidance with implemented input helpers, safe id parsing, URL encoding, CSV formula neutralization, schema backstops, and required regression-test categories.

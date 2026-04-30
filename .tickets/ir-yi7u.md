---
id: ir-yi7u
status: closed
deps: []
links: []
created: 2026-04-30T06:34:23Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-18tm
tags: [area:timesheets, area:maintenance, area:live-fragments]
---
# Decompose timesheet controller around projection and live-surface modules

Move timesheet projection fetching, render model construction, live-surface definitions, fragment refs, response helpers, and entry validation out of the monolithic controller while preserving routes and behavior.

## Design

Use the roster modules as the template: Web.Timesheets.Projection, RenderData, Responses, LiveUpdates, Paths or Dom, and Validation as needed. Start by moving pure/read-model code, then response helpers, then form validation. Keep action bodies in Web.Controller.Timesheets as orchestration.

## Acceptance Criteria

Web.Controller.Timesheets no longer owns projection definitions, fragment refs, render-model conversion, and large validation blocks; existing timesheet HTMX/live fragments keep the same ids, urls, filters, and authorization behavior; bash ./bin/in-env typecheck and focused timesheet Hspec pass.

## Notes

**2026-04-30T08:08:01Z**

Split Web.Controller.Timesheets into focused Web.Timesheets.Projection, Web.Timesheets.Responses, and Web.Timesheets.Validation modules. Controller now keeps action orchestration while projection/live-surface definitions, fragment refs, response helpers, and validation moved out. Verified with bash ./bin/in-env typecheck and bash ./bin/in-env hspec-test --match "Timesheets".

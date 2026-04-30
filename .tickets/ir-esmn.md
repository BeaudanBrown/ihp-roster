---
id: ir-esmn
status: closed
deps: [ir-wipd]
links: []
created: 2026-04-30T01:11:20Z
type: task
priority: 3
assignee: beaudan
parent: ir-2usx
tags: [area:view, area:maintenance, source:2026-04-30-health-scan]
---
# Add view chrome defaults and panel ergonomics

After the helper split, add small constructors/defaults that reduce repeated AppPanelConfig and page chrome boilerplate without changing markup.

## Design

This is a follow-up to `ir-2usx`, not part of the mechanical helper split.
Once `Application.Helper.View.Chrome` owns page/panel chrome, add small
constructors that reduce repetitive config literals without hiding important
layout choices.

Candidate additions:

- `defaultAppPanelConfig`
- `simpleAppPanel`
- `appPanelWithActions`
- helpers for common empty-state/action-row patterns if at least two call sites
  already share the same structure

Initial scan target:

- repeated `AppPanelConfig` literals in support/admin/profile views.
- action rows that vary only by title, subtitle, and button HSX.

Guardrails:

- Do not change rendered HTML, classes, heading levels, or button order.
- Avoid a large "page builder" abstraction; keep helpers small and composable.
- Add helpers only after there is a real second caller.

## Acceptance Criteria

- Repeated panel/page chrome in at least two call sites uses the new helper.
- `Application.Helper.View.Chrome` remains focused and has an explicit export
  list.
- `Application.Helper.View` stays a re-export wrapper after this ticket.
- `bash ./bin/in-env typecheck` passes.

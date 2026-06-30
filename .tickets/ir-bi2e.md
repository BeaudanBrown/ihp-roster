---
id: ir-bi2e
status: closed
deps: []
links: []
created: 2026-06-30T09:54:22Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-si7h
tags: [architecture, bepis-actions, agent-loop]
---
# Remove Bepis action name string literals

Make action wrappers derive stable action labels from the actual IHP action value instead of manually maintained Text literals.

## Design

Change wrappers to accept an action value with Data/Show-derived constructor naming or a small typed ActionLabel helper. Migrate controllers from bepisPageAction "FooAction" to bepisPageAction action/FooAction value forms. Keep IHP Controller lifecycle.

## Acceptance Criteria

No controller wrapper call has a manually typed action-name string; architecture gate checks declared action identity comes from typed action value; typecheck and strict conventions pass.


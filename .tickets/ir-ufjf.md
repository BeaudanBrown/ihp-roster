---
id: ir-ufjf
status: open
deps: [ir-mwma]
links: []
created: 2026-06-30T11:03:28Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-z0j1
tags: [architecture, bepis-actions, agent-loop]
---
# Make response helpers emit response facts

Unify response kind fact emission with the helpers that actually send redirects, HTML, HTMX fragments/OOB, JSON, files, or dialogs.

## Design

Create final Bepis response helpers or update existing feature response helpers to call emitBepisFact at the response boundary before/while performing IHP responses. Remove respondsWith* descriptive components from final action code.

## Acceptance Criteria

Actor response facts are emitted by actual response helpers; no respondsWith* calls remain; response telemetry/architecture facts come from final typed facts.

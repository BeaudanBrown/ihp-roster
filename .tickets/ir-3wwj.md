---
id: ir-3wwj
status: open
deps: [ir-ix0n]
links: []
created: 2026-05-15T02:27:08Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-nnfx
tags: [area:live-fragments, area:controller, htmx]
---
# Add live mutation and actor-response helpers

Reduce controller boilerplate for mutations that update the actor immediately and invalidate passive viewers.

## Design

Add helpers that pair a typed surface key and fragment list with the actor HTMX response, source-client header handling, post-commit broadcast, optional projection warming, and empty-fragment resync semantics.

## Acceptance Criteria

A representative mutation no longer manually threads LiveUpdateScope, liveUpdateSourceClientId, LiveFragmentRef lists, and HX-Trigger payload shape; actor and passive-viewer fragment choices are explicit and tested.


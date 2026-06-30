---
id: ir-6bfl
status: in_progress
deps: [ir-awhg]
links: []
created: 2026-05-29T03:16:07Z
type: task
priority: 2
assignee: beaudan
parent: ir-jtmv
tags: [agent-loop, profile, leave]
---
# Unify profile leave form and list actor refreshes

Make profile leave self-service successful actor updates reuse declared profile leave fragments.

## Design

Standardize profile leave form/list target ids and renderers; use OOB fragments plus toast for successful create; keep validation failures as direct form replacement where needed.

## Acceptance Criteria

Profile leave list/form actor responses no longer hand-roll unrelated OOB snippets; fragment contracts and controller specs cover target ids and success response shape.


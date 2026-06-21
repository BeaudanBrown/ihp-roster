---
id: ir-9ra7
status: open
deps: [ir-j3hy]
links: []
created: 2026-06-21T03:37:16Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-l5gk
tags: [agent-loop, frontend, typescript, docs]
---
# Document frontend TypeScript source-of-truth rules

Update local docs and guardrails for the TypeScript source/runtime split.

## Design

Update static/AGENTS.md, the README static asset section where needed, root AGENTS.md if project-wide static guidance needs adjustment, and doc drift checks if they should enforce the new TS source/runtime terminology.

## Acceptance Criteria

Docs explain that app JS source lives in frontend/ts/, generated JS lives in static/, generated JS is checked in but should not be hand-edited, frontend-build/frontend-check/frontend-watch are the supported commands, dev starts the watcher automatically, and there is no Vite dev server or true HMR requirement.


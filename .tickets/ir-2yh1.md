---
id: ir-2yh1
status: closed
deps: [ir-wwyg]
links: []
created: 2026-07-08T08:24:31Z
type: chore
priority: 1
assignee: Beaudan Brown
parent: ir-5udu
tags: [area:maintenance, cleanup-refactor]
---
# Remove source-tree build artifacts and add guardrail if needed

Remove compiled build artifacts that are present under source directories and prevent recurrence if needed.

## Design

Delete stray .hi/.o artifacts under Application/Helper/FrontendContract and related source paths. Confirm ignore rules cover these artifacts or add a narrow guard if they can recur. Do not edit generated TypeScript contracts or generated static JavaScript assets by hand.

## Acceptance Criteria

Source-tree compiled artifacts are gone. Git status shows only intended source/ignore/ticket changes. A focused lightweight check or typecheck confirms no source dependency on the artifacts.


## Notes

**2026-07-08T08:46:31Z**

Removed ignored source-tree build artifacts under Application/Helper/FrontendContract (*.hi/*.o). The files were not tracked by git. Existing root .gitignore already contains *.hi and *.o, so no new ignore rule was needed.

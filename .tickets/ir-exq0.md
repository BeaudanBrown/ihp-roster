---
id: ir-exq0
status: closed
deps: []
links: []
created: 2026-06-30T07:48:30Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-flq7
tags: [architecture, bepis-actions, agent-loop]
---
# Derive architecture wrapper metadata from Bepis types


## Notes

**2026-06-30T07:51:30Z**

Architecture facts now derive Bepis action wrapper contracts from Application/Bepis/Action.hs typed wrapper definitions and text conversion functions, and mutation policy labels from Application/Bepis/Mutation.hs text conversion functions, instead of maintaining duplicated JavaScript maps. Facts include actionWrapperContracts with typed-contract provenance. node --check and strict architecture check passed.

---
id: ir-6fzq
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
# Emit Bepis architecture contracts from typed Haskell values

Replace source-shape parsing for Bepis wrapper/kind/response/policy metadata with a Haskell-owned generated JSON contract where possible.

## Design

Define typed registries for action wrapper contracts, action/response/policy vocabularies, and mutation component contracts. Add a script that typechecks/loads Haskell-owned values and emits JSON consumed by Node architecture tools, leaving source scans only for locating usage sites.

## Acceptance Criteria

Architecture facts consume generated Bepis contract JSON first; wrapper/policy vocabularies have typed Haskell provenance; strict gate passes.


---
id: ir-qq35
status: closed
deps: [ir-52yn]
links: []
created: 2026-07-07T03:24:11Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-elys
tags: [frontend-contracts, frontend, tests, htmx]
---
# Prove generated surface action metadata is active

Add frontend, Hspec, and guardrail coverage showing generated action metadata is consumed and enforced.

## Design

Extend frontend tests so emitted `data-bepis-surface-action` metadata/config is parsed and validated through generated contracts and checked against the generated manifest. Add focused Hspec/view tests for Admin Roster Groups rendered attrs and controller response shape. Add guardrails that catch stale handwritten action metadata in migrated areas and undeclared custom HTMX usage.

Coverage should distinguish:

- standard generated action metadata;
- declared `CustomHtmx` metadata with reason;
- successful mutation actor-local refresh responses;
- validation-local/direct responses where applicable.

## Acceptance Criteria

- Frontend tests exercise generated action validators/manifests.
- Hspec/view tests prove Admin Roster Groups emits correct helper-rendered attrs and metadata.
- Controller tests prove migrated successful mutations do not return authoritative business OOB HTML.
- Guardrails catch manual migrated `hx-*` request metadata and custom HTMX that is not declared in the manifest.

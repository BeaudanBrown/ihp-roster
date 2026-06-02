---
id: ir-jmjs
status: closed
deps: []
links: []
created: 2026-06-02T01:52:35Z
type: feature
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, roster, live-fragments]
---
# Refactor roster swaps onto typed live fragments

Preserve roster horizontal scroll by replacing broad roster-content swaps with smaller typed fragments shared by HTMX/OOB and live refresh paths.

## Design

Use timesheets pattern: define smaller roster projection fragments and render both plain fragment GETs and OOB actor swaps through the typed live surface projection helpers. Assignment filters should update session without visible content swap because dropdown options are generated when dialogs open.

## Acceptance Criteria

Roster controls that do not require full shell replacement target smaller typed fragments or no swap; actor OOB swaps and live refetches share the same fragment renderer; mobile E2E verifies roster filter changes preserve horizontal scroll in both layouts.


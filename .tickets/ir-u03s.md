---
id: ir-u03s
status: open
deps: [ir-2w5m]
links: []
created: 2026-07-07T04:09:19Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-cfcr
tags: [agent-loop, research, live-fragments, frontend-surface]
---
# Inventory FrontendSurface actor response paths

Classify all current actor mutation responses and exceptions before migration.

## Design

Search registered FrontendSurface surfaces and related controllers/helpers for hx-swap-oob, respondHtml/respondHtmlProfiled, HX-Trigger, liveFragmentsRefreshEvent, invalidateTouchedResources, broadcastLiveInvalidation, and feature response helpers. Categorize each path as already actor-local invalidation, authoritative business OOB/HTML success response, validation-local direct response, non-authoritative extras only, pure view-state/refetch GET, or intentional non-FrontendSurface/legacy exception.

## Acceptance Criteria

Ticket notes list Admin simple, Admin Xero, Timesheets, Roster, Leave Requests, Profile, Billing, Support/lab paths with intended action: migrate now, exception, or follow-up. No production behavior changes.


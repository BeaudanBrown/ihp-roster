---
id: ir-k86z
status: open
deps: [ir-kayo]
links: []
created: 2026-04-30T23:32:16Z
type: task
priority: 2
assignee: beaudan
parent: ir-sryt
tags: [area:performance, area:profiling, area:e2e]
---
# Centralize profiling scenarios and expand route coverage

Replace duplicated hard-coded profiling route lists with one scenario manifest and expand read coverage across app surfaces.

## Design

Define a shared scenario manifest consumed by profile-app and profile-load. Cover current roster/timesheet/leave/Xero flows plus profile, staff edit dialogs, non-Xero admin fragments, exports, support/admin read paths, auth/passkey boundaries where useful, and representative error/redirect responses. Keep selectors and accounts in the profile seed manifest where they are data-dependent.

## Acceptance Criteria

Playwright and k6 scenario lists are generated from the same manifest or validated against it; full scenario coverage includes the major authenticated surfaces; docs list what is covered and intentionally excluded; existing profile commands keep their current names.


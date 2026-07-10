---
id: ir-blfl
status: closed
deps: []
links: []
created: 2026-07-10T00:35:35Z
type: task
priority: 2
assignee: beaudan
parent: ir-z20h
tags: [agent-loop, profile, staff, rsa, ui]
---
# Temporarily hide unfinished RSA profile sections

The RSA section appears on profile/staff profile pages before the feature is finished.

## Design

Hide the RSA accordion/section from profile pages and staff profile dialogs for now without removing underlying RSA data/model/controller code. Keep any existing direct routes or tests intact unless they explicitly assert visible profile navigation. Add a note or code comment so the section can be restored when the RSA workflow is complete.

## Acceptance Criteria

Authenticated profile and staff profile pages/dialogs no longer show the RSA section. Existing non-RSA profile behavior is unchanged. Focused profile/staff view tests are updated or added to assert the section is hidden temporarily.


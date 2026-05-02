---
id: ir-2rko
status: open
deps: []
links: []
created: 2026-05-02T01:12:29Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9jap
tags: [area:staff, area:compliance, area:pilot, venue:rooks]
---
# Add RSA document acceptance and expiry tracking

## Design

Accept and track Responsible Service of Alcohol documents as a pilot-critical staff compliance feature. Staff and managers/admins can upload RSA documents. Store document file plus metadata such as expiry date and issuing details where available. Show compliance state to managers/admins and notify before expiry. This does not permit storing TFN, bank, super, or other sensitive onboarding data.

Workstream: `docs/workstreams/rooks-pilot.md`

## Acceptance Criteria

Staff can upload their own RSA document; managers/admins can upload RSA for staff; metadata includes expiry date at minimum; managers/admins can see missing/expiring/expired RSA status; 30-day expiry reminders are sent by email and in-app notification; document access is restricted to the staff member and managers/admins as appropriate; serious onboarding data remains out of scope.

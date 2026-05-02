---
id: ir-2rko
status: closed
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

## Notes

**2026-05-02T08:10:24Z**

2026-05-02 RSA plan: Add a staff_documents foundation scoped by venue_id and staff_id, starting with document_type=rsa_statement_of_attainment, private file metadata, status pending/verified/rejected/expired, issue_date, expiry_date, uploader/verifier audit fields, rejection reason, and reminder_sent_at. Reuse the existing upload/document pattern if present; otherwise add private staff-documents storage restricted to the staff member plus venue managers/admins/owners/support. UI should add staff upload/replace, manager/admin compliance indicators, and an admin list filtered by missing/expiring/expired. Add a daily idempotent job for 30-day and expired RSA reminders once notification hooks are confirmed. Tests should cover tenant integrity, upload access, status changes, reminder selection, and that TFN, bank, super, and broader onboarding data remain out of scope.

**2026-05-02T09:05:37Z**

Implemented RSA document foundations: venue-scoped staff_documents schema/migration with RSA type/status enums, no TFN/bank/super fields, tenant integrity and hard-delete guard; staff/manager upload/download/review controller with audit events and access checks; profile/staff/admin compliance UI using shared RSA panels; daily idempotent RSA reminder sweep/job/mail path for 30-day and expired documents; focused schema/domain/controller tests. In-app compliance notification is surfaced as status badges/manager compliance views because the app has no durable notification inbox concept.

---
id: ir-kjht
status: open
deps: [ir-0p4g]
links: []
created: 2026-06-02T07:20:14Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:myob, area:providers, auth]
---
# Implement MYOB connection setup and company-file validation

Wire MYOB direct API connection into the Payroll provider foundation.

## Design

Add MYOB provider selection, full-page OAuth start/callback, state validation, businessId/company-file metadata capture, token persistence, refresh support, disconnect/reauthorize behavior, and company-file credential state handling based on the spike decision. Keep MYOB my.MYOB credentials out of Bepis.

## Acceptance Criteria

Venue owners/super-admins can connect/disconnect MYOB from Payroll. The connection records businessId/company-file metadata and accurately reports active, reauthorization_required, credential_required, credential_rejected, or disconnected states. Access control and token storage tests pass.


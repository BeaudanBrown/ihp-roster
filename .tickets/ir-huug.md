---
id: ir-huug
status: open
deps: []
links: [ir-176p, ir-mjov]
created: 2026-06-02T07:20:13Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, area:payroll, area:providers, area:xero, area:myob, architecture]
---
# Payroll provider abstraction and MYOB direct API feature parity

Canonical epic for replacing Xero-specific downstream payroll integration flows with provider-neutral payroll provider interfaces, migrating the existing Xero integration onto that foundation, then implementing MYOB direct API support with feature parity where provider capabilities allow.

## Design

Key decisions: user-facing navigation becomes Payroll; each venue has at most one active payroll provider at a time; Xero must be functional on the provider-neutral foundation before MYOB implementation begins; MYOB scope is direct online MYOB Business/AccountRight API only, not Desktop, AccountEdge, EXO, TXT, or CSV exports; MYOB paid developer access is assumed available for planning but must be verified by the MYOB spike; cftoken/company-file credential storage is not decided and must be resolved from sandbox evidence plus security requirements. Downstream Payroll UI/services should consume provider-neutral contracts while Xero, MYOB, and future providers own provider-specific API internals.

## Acceptance Criteria

Xero connection, reference sync, mapping, managed pay item, preparation, readiness, preview, submission, and correction behavior work through provider-neutral Payroll boundaries without regression. MYOB direct API implements the same Bepis payroll outcomes where MYOB supports them, including OAuth, reference sync, wage/pay item management, employee wage-category readiness, period selection, preview, audited timesheet submission, and correction/update safeguards. Living docs/specs/ADRs describe the provider model and no downstream flow needs to know Xero or MYOB internals except through provider adapters.


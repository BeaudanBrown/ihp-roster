---
id: ir-jhsv
status: open
deps: []
links: [ir-23k7]
created: 2026-04-30T06:34:41Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-18tm
tags: [area:xero, area:admin, area:maintenance, area:architecture]
---
# Move Xero admin web response code out of Application namespace

Correct the remaining Xero admin layer inversion where Application.Xero.Admin modules import Web.Controller.Prelude and perform request/response, redirect, permission, toast, and HTMX work.

## Design

Keep domain/read-model/service logic under Application.Xero.*. Move web action and response plumbing to Web.Controller.Admin.Xero.* modules, leaving Web.Controller.Admin.Xero as a thin re-export or orchestration boundary if useful. Link this as a follow-up to the closed admin/Xero split because the file-size split landed but the namespace boundary still leaks.

## Acceptance Criteria

Application.Xero.Admin modules no longer import Web.Controller.Prelude for controller behavior; web responses and params live under Web.Controller.Admin.Xero; Xero admin routes, action types, DOM ids, OOB fragments, and tests remain stable.

# Xero Integration

## Purpose

`Application/Xero/` owns Xero OAuth connection support, reference data, managed
pay item logic, keepalive behavior, and timesheet preview/submission services.

## Modules

- `Connection.hs` - connection and token boundary.
- `Keepalive.hs` - recurring token/connection health support.
- `Admin/ReferenceData.hs` - reference data sync/service logic.
- `Admin/PayItems.hs` - managed pay item behavior.
- `Admin/ReadModel.hs` - admin read models.
- `Timesheets/Preview.hs` - Xero-shaped preview payloads.
- `Timesheets/Submission.hs` - submission state and API orchestration.

Web request/response behavior belongs under `Web/Controller/Admin/Xero/`.

## Related Docs

- `SPEC.md`
- `AGENTS.md`
- `Web/Controller/Admin/Xero/AGENTS.md`
- `docs/workstreams/xero-payroll.md`
- `docs/workstreams/rooks-pilot.md`

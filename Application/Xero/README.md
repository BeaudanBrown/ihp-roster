# Xero Integration

## Ownership

`Application/Xero/` owns Xero OAuth/token handling, reference synchronization,
managed/imported pay items, and the preparation/preview/submission services for
Payroll AU timesheets. Web request and response behavior belongs under
`Web/Controller/Admin/Xero/`.

## Start Here

- `Connection.hs` — OAuth connection and token boundary.
- `ReferenceSyncJob.hs`, `ReferenceTrust.hs`, and `Admin/ReferenceData.hs` —
  durable synchronization, snapshot trust, and provider-availability updates.
- `Admin/ReadModel.hs` — connection and preparation read models.
- `Timesheets/Prepare.hs` — guided preparation entry point;
  `Timesheets/Preview.hs` and `Timesheets/Submission.hs` are internal services.
- `PayrollSourceKey.hs` — canonical Xero source/rate identity suffix.

Follow imports from those modules for narrower policy and persistence seams.

## Related Docs

- `SPEC.md` — durable authorization, synchronization, and payroll contracts.
- `AGENTS.md` and `Web/Controller/Admin/Xero/AGENTS.md` — editing rules.
- `vendor/xero-openapi/README.md` — provider-contract provenance.

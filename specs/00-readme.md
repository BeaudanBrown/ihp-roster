# IHP Application Specifications

This folder contains product, domain, compliance, and acceptance specifications
that span more than one code subsystem.

Implemented subsystem behavior belongs in local `SPEC.md` files beside code.
Future feature-stream design belongs in `docs/workstreams/`. Historical plans
live in `docs/archive/plans/`.

Technical baseline:

- IHP (Haskell MVC)
- PostgreSQL
- HSX views
- Bootstrap 5.3.8

## Canonical decisions

1. UI requirements target **Bootstrap 5**.
2. Pay engine uses a **Mixed architecture**:
   - PostgreSQL functions for canonical pay calculations.
   - Haskell for orchestration/report shaping.
3. Late-to-Early conflict is based on **start-to-start gap**.
4. Late-to-Early threshold is a **global venue config** value.
5. `week_offset_epoch` is a **global fixed epoch**.
6. Weekend multipliers **stack** with penalties.
7. Kitchen flag is out of scope.
8. Timesheet time input requires **exact 15-minute increments**.
9. Trial staff are placeholders only; no conversion flow.
10. **Managers, Venue Admins and Venue Owners can publish** rosters.
11. Initial commercial model is **local managed SaaS with venue as the current customer boundary**, not public self-serve SaaS.
12. Venue business roles live on **`venue_memberships`**, not on `users`.
13. Initial privileged access uses a **founder-managed venue bootstrap flow**, not first-user auto-admin.
14. Payroll-adjacent records use **correction-safe history**, not silent destructive overwrite.
15. Pay and configuration behavior must remain **historically reproducible** for past periods and exports.
16. Venue admin bulk config save creates a new **immutable pay/config snapshot version**.

## Document Map

- `01-product-scope.md`
- `02-domain-model.md`
- `03-access-control-and-auth.md`
- `04-roster-and-conflict-rules.md`
- `05-timesheets-and-leave.md`
- `06-pay-engine.md`
- `07-ui-bootstrap-spec.md`
- `08-ihp-implementation-spec.md`
- `09-testing-and-acceptance.md`
- `10-au-saas-security-privacy-compliance/`
- `11-first-client-document-pack/`
- `12-performance-profiling.md`

## Local Living Specs

High-churn subsystem contracts live near their code:

- `Web/RosterWeeks/SPEC.md`
- `Web/Timesheets/SPEC.md`
- `Web/LeaveRequests/SPEC.md`
- `Application/Helper/Export/SPEC.md`
- `Application/Xero/SPEC.md`
- `Application/Helper/LiveUpdate.SPEC.md`

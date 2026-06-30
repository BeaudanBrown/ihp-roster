---
id: ir-awhg
status: closed
deps: [ir-ka82]
links: []
created: 2026-05-29T03:16:07Z
type: task
priority: 2
assignee: beaudan
parent: ir-jtmv
tags: [agent-loop, leave, manager]
---
# Remove leave page fragment and unify manager leave content responses

Migrate the manager leave requests page content to the shared fragment helper.

## Design

Remove LeaveRequestsProjectionPage from the live fragment system, keep content as the manager page fragment, and make approve/deny/create success return OOB content plus extras through the shared helper.

## Acceptance Criteria

No live page/shell fragment remains for leave requests; manager leave content endpoint returns the exact target node; approve/deny HTMX responses use OOB content from the shared renderer; focused Hspec passes.


## Notes

**2026-06-30T00:00:14Z**

Implemented. Removed the obsolete LeaveRequestsProjectionPage/buildLeaveRequestsPageFragmentRef path and the now-unused renderLeaveRequestsContentFragmentOob helper. Manager leave approve/deny/create HTMX success now renders LeaveRequestsProjectionContent through respondWithTypedLiveSurfaceFragments with OOB outerHTML plus dialog clear/toast extras. Review action forms now use hx-swap=none to avoid double-swapping actor OOB responses, and duplicated approve/deny form markup is centralized. Fragment GET still returns the plain leave-requests-content target; archive pagination swapOob=true remains the documented local subfragment exception. Verification passed: bash ./bin/in-env typecheck; bash ./bin/in-env hspec-test --match 'LeaveRequests'.

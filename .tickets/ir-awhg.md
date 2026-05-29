---
id: ir-awhg
status: open
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


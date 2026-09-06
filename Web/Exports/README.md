# Export Web Workflows

`Web/Controller/Exports.hs` remains the IHP lifecycle and permission-response
seam. Saved Workbook request coordination belongs here; export generation,
downloads and unsaved sheet controls retain their existing owners.

- `WorkbookConfigurations.hs` adapts the declared create/edit AppShell requests,
  constructs the appropriate submitted or fallback draft, and invokes the
  existing typed mutation. Its closed `WorkbookEditorOutcome` separates invalid
  transport, semantic rejection and committed create/edit completion.
- `Mutations.hs` owns locks, transactions and durable touched-resource
  publication. Delete already has a sufficiently deep interface and needs no
  additional workflow wrapper.
- `Responses.hs` owns saved-configuration feedback, dialogs, native navigation
  and actor-only completion. Views remain in
  `Web/View/Admin/PayrollWorkbookConfigurationDialog.hs`; persistence remains in
  `Application/Helper/Export/PayrollWorkbookConfiguration.hs`.

## Editing Constraints

Keep access and writability checks before the request-facing workflows. Parsed
fields are not authority: mutations retain their current-venue lookup, locking
and revalidation. In particular, edit must not pre-load or validate a name before
its mutation's scoped lock. Transport failure, unknown family, missing record
and stale revision intentionally retain different draft values and precedence.

The Web workflow consumes the existing nominal request bundles internally rather
than exposing duplicate transport DTOs. Its outcome reuses the existing dialog
model; do not move HTTP or view dependencies into Application persistence.
Responses run after the mutation returns, never inside its transaction. Returning
a rejected outcome must not hide a post-write exception or add a second passive
publication. Preserve the shared actor-refresh planner and requester-only extras.

## Verification

Use the public request characterizations in
`Test/Controller/Exports/WorkbookConfigurationsSpec.hs`, persistence/failure tests
in `Test/PayrollWorkbookConfigurationSpec.hs`, and existing Exports/Users tests.
For browser integration run the export download and authorization Playwright
specs after verifying the current worktree's runtime identity.

See [export contracts](../../Application/Helper/Export/SPEC.md) and
[controller rules](../Controller/AGENTS.md).

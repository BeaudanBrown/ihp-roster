# AppJob boundary

Bepis uses IHP's unmodified job workers, retry counter, maximum attempts and
backoff strategy. Ordinary `AppJob` work has four slots per worker process;
`DaysheetCaptureJob` has eight dedicated slots so pre-cutoff waits cannot occupy
the ordinary/mail pool. Both are registered in `Web.Worker`. It does not patch IHP
or implement a parallel scheduler. Database and host resources remain shared.

`Application.Async.Registry.dispatchAppJob` is the ordinary application boundary.
The dedicated Daysheet instance enters the same telemetry/safe-error boundary;
legacy AppJob capture tasks perform only an atomic queue handoff. Known job and provider outcomes are projected to payload-free `AppJobError`
classifications. The boundary records bounded `AppError` telemetry and throws one
private exception whose `Show` value contains only the generated code and safe
message. Unexpected synchronous exceptions are replaced by the generic safe
classification; asynchronous cancellation remains native to IHP.

`AppError` retry directives describe the classification but do not override IHP
scheduling. Provider-specific delayed continuations remain explicit only where
the provider contract requires them, notably Xero reference-sync `Retry-After`
and its bounded jitter window.

Persisted `app_jobs.last_error`, job results, provider mirrors, and user-facing
copy must never contain raw provider payloads, credentials, SQL values, parser
diagnostics, or exception text.

The host-local watchdog requests a minute-bucketed `worker_heartbeat` job through
the least-privilege database function. Successful dispatch through this registry
is the worker heartbeat authority. The watchdog itself is a systemd service in
`bepis-dotfiles`, outside this queue; it never executes customer or payroll work.

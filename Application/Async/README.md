# AppJob boundary

Bepis uses IHP's unmodified `Job AppJob` worker, retry counter, maximum attempts,
and backoff strategy. It does not patch IHP or implement a parallel scheduler.

`Application.Async.Registry.dispatchAppJob` is the final application boundary.
Known job and provider outcomes are projected to payload-free `AppJobError`
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

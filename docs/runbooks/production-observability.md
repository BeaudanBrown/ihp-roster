# Production Observability Runbook

This runbook operates Bepis OpenTelemetry capture, storage, and query access. It
covers the production app/worker, host-local Collector, Tempo and Loki, the
separate NAS Grafana frontend, and bounded agent queries. Performance experiment
procedures remain in [Performance Profiling](./performance-profiling.md).

The implementation authority is:

- `Config/nix/modules/ihp-roster.nix` for production services and network policy;
- `Config/nix/hosts/production/configuration.nix` for the production enablement;
- `scripts/observability/query.mjs` for bounded agent access;
- `Application/Helper/Telemetry.hs` and its semantic helpers for emitted data;
- `modules/services/grafana/{nas,dashboards}.nix` in the separate
  `nix-dotfiles` repository for the human frontend.

Do not use this runbook to deploy unrelated application changes, reset data,
delete telemetry state, inspect private SOPS contents, or expose a temporary
public diagnostics endpoint.

## Security Model

### Trust boundaries

```text
app + worker
  -> 127.0.0.1:4317/4318 Collector ingestion
  -> 127.0.0.1 Tempo/Loki ingestion and local storage
  -> tailscale0-only Tempo :3200 and GET-only Loki proxy :3101
  -> authenticated tailnet-only NAS Grafana

approved agent
  -> fixed bounded Tempo/Loki GET requests over the tailnet
  -> private expiring local artifact
```

The production host has these boundaries:

| Interface | Port | Purpose | Required exposure |
| --- | ---: | --- | --- |
| Public | 22, 80, 443 | SSH and customer application | Normal host policy |
| `tailscale0` | 3200 | Tempo query API | Tailnet only |
| `tailscale0` | 3101 | nginx GET-only Loki query proxy | Tailnet only |
| Loopback | 4317, 4318 | Collector OTLP ingestion | Never remote |
| Loopback | 13133, 8888 | Collector health and metrics | Never remote |
| Loopback | 4327, 4328, 9095 | Tempo ingestion/internal gRPC | Never remote |
| Loopback | 3100, 9096 | Loki ingestion/internal gRPC | Never remote |

Tempo and Loki do not add application-level authentication. Their production
query authorization is the Tailscale network boundary and host firewall. Never
open query or ingestion ports in the general firewall. Never proxy OTLP, Loki
write endpoints, arbitrary host paths, or Collector administration through
Grafana or nginx.

Grafana is a separate consumer. It binds to NAS loopback and is published only
through the authenticated tailnet virtual host at `https://grafana.bepis.lol`.
A Grafana or NAS outage must not interrupt production capture. Grafana account
and SOPS credential operation belongs to `nix-dotfiles`; never copy credentials
into this repository or an incident artifact.

### Retained data

Normal production tracing uses `parentbased_traceidratio` at `0.01`. Sampling
means production traces are diagnostic samples, not a request ledger or exact
traffic count. Profiling remains disabled during ordinary production operation.

Allowed trace data is low-cardinality operational metadata: service and deploy
identity, closed action/route and operation names, HTTP method/status class,
response kind, bounded aggregate counts, job attempt state, and selected provider
outcomes. Telemetry must never contain:

- names, emails, customer or venue identifiers;
- query strings, free-form parameters, raw URLs or request targets;
- cookies, authorization headers, credentials or tokens;
- request/response bodies, provider payloads or addresses;
- SQL text, SQL parameters or persisted query results;
- raw exception text, deduplication keys, provider IDs or job payloads.

New attributes must use a closed vocabulary or bounded aggregate. Do not turn a
span attribute into a Loki label without a cardinality review. A new provider,
job, route, journal unit, retained log field, or unredacted message requires a
specific privacy/cardinality review and tests before production enablement.

Only `app.service` and `worker.service` journals enter the Collector. Before
export, every body becomes `[redacted production journal event]`; only the
allowlisted systemd unit, priority and syslog identifier remain. Nginx access
logs are excluded because request targets can contain customer or
high-cardinality data. Trace-to-log navigation is a service and time-window
lookup, not proof that a log row was caused by that trace.

Treat Grafana views, screenshots, agent artifacts, and profile output as private
operational data even after sanitization. Do not publish them in issues or chat.
In particular, isolated profile `server.log` files can contain framework debug
SQL structure and are not safe production artifacts.

## Modes

| Mode | Configuration | Use |
| --- | --- | --- |
| Disabled | `otel.enable = false`, `profiling.enable = false` | No app/worker tracer provider or diagnostic profiling |
| Lightweight | `otel.enable = true`, profiling disabled | Ordinary sampled production tracing |
| Diagnostic | `profiling.enable = true` | Short, explicitly approved diagnostic window only |

The disabled app path does not create a provider, exporter, worker thread, or
timer. Enabled telemetry is fail-open: initialization, Collector, Tempo, Loki,
Grafana, export, flush, and shutdown failures must not replace application work.
App and worker want the Collector but do not require it.

Diagnostic profiling adds timing, render counters, HTML sizes, query aggregates,
and runtime evidence. It is expensive and can expose internal span names through
profile-gated `Server-Timing`. Never leave it enabled for ordinary public
traffic. Prefer an isolated profile database and the profiling runbook.

## Enable Or Change Production Capture

The reviewed production shape is:

```nix
fileSystems."/".options = [ "prjquota" ];
services.tailscale.enable = true;

services.ihpRoster.observability = {
  otel = {
    enable = true;
    sampler = "parentbased_traceidratio";
    samplerArg = "0.01";
  };
  profiling.enable = false;
  collector.enable = true;
  tempo = {
    enable = true;
    queryAddress = "0.0.0.0";
  };
  loki = {
    enable = true;
    queryAddress = "0.0.0.0";
  };
};
```

`0.0.0.0` is acceptable for the two query listeners only because the NixOS
module opens ports 3101/3200 exclusively on `tailscale0`. Collector ingestion
must remain `127.0.0.1`. Production project quotas require the backing root
filesystem to retain `prjquota`.

Before applying a production configuration:

```bash
bash ./bin/in-env observability-production-check
bash ./bin/in-env observability-backend-smoke
bash ./bin/in-env deployment-module-check
```

The first command validates generated Collector, Tempo and Loki configuration,
firewall boundaries, retention, quotas, and rejected unsafe module variants. The
smoke command starts disposable localhost services and proves OTLP trace export
plus mandatory log redaction. Neither command queries or changes production.
Use the deployment owner's normal reviewed NixOS deployment procedure after
these checks; this repository intentionally does not define an ad hoc SSH
switch command.

After deployment, an authorized operator on the production host checks:

```bash
sudo systemctl is-active \
  app.service worker.service \
  opentelemetry-collector.service tempo.service loki.service tailscaled.service

curl --fail --silent --show-error http://127.0.0.1:13133/
curl --fail --silent --show-error http://127.0.0.1:3200/ready
curl --fail --silent --show-error http://127.0.0.1:3100/ready
curl --fail --silent --show-error http://127.0.0.1:3101/ready

sudo systemctl show \
  opentelemetry-collector.service tempo.service loki.service \
  --property=ActiveState,SubState,MemoryCurrent,MemoryPeak,StateDirectoryQuota
```

Use `sudo ss -lntp` to confirm OTLP, Collector health/metrics, backend ingestion,
and internal gRPC ports are loopback-only. Tempo 3200 and the Loki proxy 3101
may listen broadly, but the NixOS firewall must list them only under
`networking.firewall.interfaces.tailscale0.allowedTCPPorts`.

From an authorized tailnet workstation, verify GET access and the Loki write
denial:

```bash
export BEPIS_PRODUCTION_HOST='<MagicDNS name or Tailscale IP>'

curl --fail --silent --show-error \
  "http://${BEPIS_PRODUCTION_HOST}:3200/ready"
curl --fail --silent --show-error \
  "http://${BEPIS_PRODUCTION_HOST}:3101/ready"

test "$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --request POST \
  "http://${BEPIS_PRODUCTION_HOST}:3101/loki/api/v1/query_range")" = 405
```

Also confirm from a device outside the tailnet that ports 3101/3200 and
`grafana.bepis.lol` are unavailable. A test from a tailnet-connected device does
not prove public denial. Do not send a test payload to OTLP or Loki write ports;
verify that 4317/4318, 3100 and 4327/4328 are unreachable remotely.

## Routine Health And Capacity

On the production host, inspect only bounded service status and recent service
logs:

```bash
sudo systemctl status \
  opentelemetry-collector.service tempo.service loki.service \
  --no-pager

sudo journalctl \
  -u opentelemetry-collector.service -u tempo.service -u loki.service \
  --since '-15 minutes' --no-pager --lines=200

sudo systemctl show \
  opentelemetry-collector.service tempo.service loki.service \
  --property=ActiveState,SubState,NRestarts,MemoryCurrent,MemoryPeak,TasksCurrent

sudo du -sh \
  /var/lib/opentelemetry-collector/queue \
  /var/lib/ihp-roster/tempo \
  /var/lib/ihp-roster/loki
```

Do not paste host journals into tickets. Report only bounded service state,
counts, timestamps and sanitized failure categories.

Resource and retention ceilings are:

| Component | Memory ceiling | State quota | Retention/queue policy |
| --- | ---: | ---: | --- |
| Collector | 320 MiB | 256 MiB | 2,048-item persistent queue per backend; retry up to five minutes |
| Tempo | 512 MiB | 4 GiB | Seven-day local block retention; 100 MB block ceiling |
| Loki | 512 MiB | 4 GiB | Seven-day retention/query window; 4 MiB/s steady, 8 MiB burst |

A full queue, quota, or unavailable backend may drop telemetry; it must not take
down Bepis. Do not increase retention or quotas during an incident merely to
hide sustained volume. First identify whether a new span, attribute, journal
source, retry loop, or query pattern changed volume.

## Human Queries In Grafana

Connect to the tailnet, authenticate at `https://grafana.bepis.lol`, and use the
provisioned **Bepis** folder:

- **Bepis request traces** — slow actions, failures, HTMX responses and recent actions;
- **Bepis roster hot paths** — roster actions, read models and render boundaries;
- **Bepis jobs and provider boundaries** — attempts, selected providers, live updates and exports;
- **Bepis diagnostic profile traces** — profile-gated spans from approved runs;
- **Bepis production log occurrence** — fully redacted journal occurrence and severity.

Tempo dashboards can select production or the reverse-tunnelled development
source. Development currently has no Loki. A production trace's **Logs for this
span** link selects `service_name=ihp-roster` over the span window plus 30
seconds on either side. Nearby log rows are temporal context only.

Dashboards and data sources are immutable Nix provisioning. Do not edit them in
the UI. Change `nix-dotfiles`, run its checks, deploy NAS through its normal
reviewed procedure, and retain stable dashboard/data-source UIDs.

## Bounded Agent Queries

Agent commands default to the current development workspace. Production is
always explicit and accepts only a tailnet origin on the fixed query ports:

```bash
export BEPIS_PRODUCTION_TEMPO_QUERY_URL='http://<tailnet-host>:3200'
export BEPIS_PRODUCTION_LOKI_QUERY_URL='http://<tailnet-host>:3101'

bash ./bin/in-env otel-recent \
  --target=production --minutes=5 --limit=10
bash ./bin/in-env otel-trace \
  --artifact-dir=.pi/tmp/observability-query/<artifact> \
  --trace-ref=<safe-trace-ref>
bash ./bin/in-env otel-logs \
  --artifact-dir=.pi/tmp/observability-query/<artifact> \
  --trace-ref=<safe-trace-ref>

bash ./bin/in-env otel-compare \
  --target=production \
  --before-end=<before-window-end-ISO-8601> \
  --after-end=<after-window-end-ISO-8601> \
  --minutes=5 --limit=10
```

Use the safe trace reference printed by the preceding command, never a raw Tempo
trace ID. Follow-up commands validate required provenance, target consistency,
private directory/file modes, and the 24-hour expiry. Production query tools
issue only fixed GET requests; they expose no arbitrary TraceQL, LogQL, Grafana,
write, OTLP, URL-path, or credential surface.

The materialized artifact is capped at 20 traces, 2,000 spans, 500 spans per
trace, 200 log rows, 8 MiB total backend response, and a 15-minute window within
the last seven days. Attributes/resources are allowlisted, unknown values are
hashed, events and free-form status messages are removed, IHP response-control
status is reduced to the fixed `ResponseException` marker, raw trace IDs are
replaced, and Loki output is rejected unless every body is the redaction marker. Artifacts
remain private under `.pi/tmp/observability-query/` and expire after 24 hours.
Do not copy them to a public location.

An absent result is not proof that no request or failure occurred: production is
sampled, export is bounded, and outages can drop evidence. Compare only matched
workloads and deployment identities. Use customer-visible behavior and durable
business/audit state—not telemetry—as the authority for business outcomes.

## Incident Diagnosis

1. Record the target, UTC time window, deployed revision and customer-visible
   symptom without copying customer data into the investigation.
2. Check service state, restarts, memory and state-directory use.
3. Materialize a five-minute production window with `otel-recent`.
4. Inspect one safe trace reference with `otel-trace`.
5. If Loki is healthy, append bounded temporal log counts with `otel-logs`.
6. Use Grafana for interactive trace shape and provisioned dashboard views.
7. Compare matched windows only when workload, host and deployment context make
   the comparison meaningful.
8. If evidence is absent, report sampling/export/backend limitations rather than
   weakening privacy controls or enabling unbounded queries.

For a suspected telemetry privacy breach, stop capture first as described below,
preserve existing state, and open a dedicated incident/privacy issue before
adding fields, querying broader logs, or sharing artifacts.

## Disable, Contain, And Recover

Choose the narrowest declarative action:

| Objective | Configuration change | Preserved behavior |
| --- | --- | --- |
| Remove remote query access | Set both `queryAddress = null` | Local capture and storage continue |
| Stop app/worker traces | Set `otel.enable = false`; keep profiling false | Redacted journal capture can continue |
| Stop all new capture | Disable OTel, profiling and Collector; leave Tempo/Loki enabled with query addresses null | Existing local data remains available on-host |
| Stop the complete stack | Disable OTel, profiling, Collector, Tempo and Loki | State directories remain for recovery |

Collector requires both backends when enabled; do not disable only Tempo or Loki
while leaving Collector enabled. Apply the changed NixOS configuration through
the normal reviewed deployment path.

For an urgent suspected collection/privacy fault, an authorized production-host
operator may contain new retention immediately:

```bash
sudo systemctl stop opentelemetry-collector.service
```

The application remains fail-open while export fails. Follow immediately with a
declarative change disabling `otel`, `profiling`, and `collector`, then restart app/worker via
the normal deployment. If stored data itself may be exposed, stop Tempo and Loki
too; their state directories remain intact:

```bash
sudo systemctl stop tempo.service loki.service
```

Do not stop shared nginx merely to disable the Loki proxy because nginx also
serves the customer application. Do not delete `/var/lib/ihp-roster/tempo`,
`/var/lib/ihp-roster/loki`, or the Collector queue as an emergency response.
Do not reset the database; telemetry state is independent of customer data.

Recovery procedure:

1. Keep affected state directories and record bounded service/quota evidence.
2. Correct the configuration, privacy fault, capacity issue, or backend outage.
3. Re-run `observability-production-check` and `observability-backend-smoke` on
   the exact revision intended for deployment.
4. Apply the reviewed configuration.
5. Start or restart Collector, Tempo and Loki only through that configuration;
   use `systemctl reset-failed` if an already-correct unit remains failed.
6. Repeat localhost readiness, tailnet access, remote-ingestion denial, bounded
   agent query, and Grafana checks.
7. Treat gaps during the outage as lost telemetry. Never reconstruct business
   events from sampled traces or temporal logs.

If storage is corrupt or quotas remain exhausted, stop new capture, preserve a
copy or snapshot according to host backup policy, and obtain explicit operator
approval for any deletion or restore. Never improvise `rm -rf`, shorten retention
below policy, or replace local state as part of routine diagnosis.

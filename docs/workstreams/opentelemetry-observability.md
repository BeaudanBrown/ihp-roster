# Production OpenTelemetry Observability

Epic: [#90](https://github.com/BeaudanBrown/ihp-roster/issues/90).
Architecture and implemented local tooling live in
`docs/architecture/observability.md` and executable profile commands. This
workstream retains only unresolved production intent.

## Open Issues

- [#40](https://github.com/BeaudanBrown/ihp-roster/issues/40) — tailnet-only NAS
  Grafana frontend.
- [#13](https://github.com/BeaudanBrown/ihp-roster/issues/13) — dashboards and
  trace/log correlation.
- [#79](https://github.com/BeaudanBrown/ihp-roster/issues/79) — production
  runbook, retention, and security model.
- [#28](https://github.com/BeaudanBrown/ihp-roster/issues/28) — retire the custom
  profiling-header spine after parity.

GitHub owns sequencing and implementation status.

The production Collector, local Tempo/Loki storage, and tailnet-only query
firewall boundary are implemented in `Config/nix/modules/ihp-roster.nix`.
Remaining work consumes that backend.

## Production Boundary

```text
Bepis app
  -> localhost-only OTLP
  -> production Collector/Alloy
  -> production Tempo + Loki
  -> query APIs bound to tailscale0
  -> tailnet NAS/personal Grafana
```

- OTLP ingestion must not be public. Production query endpoints and Grafana are
  tailnet-only.
- The production backend starts with seven-day retention, hard project quotas,
  tailnet-only read access, closed low-cardinality telemetry attributes, and
  fully redacted journal bodies. Any broader log content requires a new privacy
  review before enablement.
- Trace/log correlation should let an operator move from a failed or slow
  request to related logs without making customer or credential data searchable.
- Metrics remain secondary until stable, low-cardinality operational signals are
  identified.
- Existing profile headers remain compatibility diagnostics until OTel artifacts
  and production workflows provide equivalent evidence; retirement must not
  remove useful browser-development timing accidentally.

## Integration Points

- `services.ihpRoster.observability` NixOS options and production host config.
- Collector/Tempo/Loki services on the production host.
- Grafana provisioning in the separate nix-dotfiles host.
- `docs/architecture/observability.md` and
  `docs/runbooks/performance-profiling.md` after behavior lands.
- Operator procedures for enable/disable, storage, retention, incident access,
  and data disclosure.

## Exit Criteria

- Production capture/storage and tailnet query boundaries are deployed and
  verified.
- Grafana can inspect production traces/logs through provisioned data sources.
- Dashboards and correlation conventions support incident diagnosis.
- Security, PII/cardinality, retention, and rollback procedures are reviewed.
- `Server-Timing` is retained only as profile-gated compatibility; legacy
  `X-Profile-Counters` and `X-Profile-Response-Bytes` are retired after local
  OpenTelemetry artifact parity.

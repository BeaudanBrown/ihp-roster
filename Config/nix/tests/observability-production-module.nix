let
  verificationSource = import ./verification-source.nix { root = ../../..; };
  flake = builtins.getFlake (builtins.unsafeDiscardStringContext (toString verificationSource));
  lib = flake.inputs.nixpkgs.lib;
  evaluate =
    {
      collectorEnable ? true,
      tempoEnable ? true,
      lokiEnable ? true,
      receiverAddress ? "127.0.0.1",
      memoryLimitMiB ? 256,
      memorySpikeLimitMiB ? 64,
      journalUnits ? [ "app.service" "worker.service" ],
      tempoQueryAddress ? "0.0.0.0",
      lokiQueryAddress ? "0.0.0.0",
      projectQuota ? true
    }:
    lib.nixosSystem {
      system = builtins.currentSystem;
      modules = [
        flake.nixosModules.default
        ({ ... }: {
          boot.isContainer = true;
          networking.hostName = "bepis-observability-check";
          fileSystems."/" = { device = "none"; fsType = "tmpfs"; options = if projectQuota then [ "prjquota" ] else [ "defaults" ]; };
          services.ihpRoster = {
            enable = true;
            production = true;
            domain = "observability.example.test";
            baseUrl = "https://observability.example.test";
            databaseUrl = "postgresql:///observability_module_check";
            enableMigrations = false;
            observability = {
              otel.enable = true;
              collector = {
                enable = collectorEnable;
                inherit receiverAddress memoryLimitMiB memorySpikeLimitMiB journalUnits;
              };
              tempo = { enable = tempoEnable; queryAddress = tempoQueryAddress; };
              loki = { enable = lokiEnable; queryAddress = lokiQueryAddress; };
            };
          };
        })
      ];
    };
  assertionsPass = evaluated: builtins.all (item: item.assertion) evaluated.config.assertions;
  valid = evaluate { };
  cfg = valid.config;
  collector = cfg.services.opentelemetry-collector.settings;
  getOnlyPolicy = ''
    if ($request_method != GET) { return 405; }
  '';
  invalidConfigurations = [
    (evaluate { collectorEnable = true; tempoEnable = false; })
    (evaluate { collectorEnable = true; lokiEnable = false; })
    (evaluate { receiverAddress = "0.0.0.0"; })
    (evaluate { memoryLimitMiB = 64; memorySpikeLimitMiB = 64; })
    (evaluate { journalUnits = [ "nginx.service" ]; })
    (evaluate { projectQuota = false; })
  ];
in
assert assertionsPass valid;
assert builtins.all (evaluated: !(assertionsPass evaluated)) invalidConfigurations;
assert cfg.services.tempo.enable;
assert cfg.services.loki.enable;
assert cfg.services.opentelemetry-collector.enable;
assert collector.service.telemetry.metrics.readers == [ {
  pull.exporter.prometheus = { host = "127.0.0.1"; port = 8888; };
} ];
assert collector.receivers.otlp.protocols.http.endpoint == "127.0.0.1:4318";
assert collector.receivers.journald.units == [ "app.service" "worker.service" ];
assert builtins.any (attribute: attribute.key == "service.name" && attribute.value == "ihp-roster") collector.processors."resource/logs".attributes;
assert collector.exporters."otlphttp/tempo".endpoint == "http://127.0.0.1:4328";
assert collector.exporters."otlphttp/loki".endpoint == "http://127.0.0.1:3100/otlp";
assert collector.exporters."otlphttp/tempo".sending_queue.storage == "file_storage";
assert cfg.services.tempo.settings.server.http_listen_address == "0.0.0.0";
assert cfg.services.loki.configuration.server.http_listen_address == "127.0.0.1";
assert builtins.length cfg.services.nginx.virtualHosts."bepis-loki-tailnet-query".listen == 1;
assert (builtins.head cfg.services.nginx.virtualHosts."bepis-loki-tailnet-query".listen).addr == "0.0.0.0";
assert (builtins.head cfg.services.nginx.virtualHosts."bepis-loki-tailnet-query".listen).port == 3101;
assert cfg.services.nginx.virtualHosts."bepis-loki-tailnet-query".locations."/loki/api/v1/".extraConfig == getOnlyPolicy;
assert cfg.services.nginx.virtualHosts."bepis-loki-tailnet-query".locations."/loki/api/v1/".proxyPass == "http://127.0.0.1:3100";
assert cfg.services.nginx.virtualHosts."bepis-loki-tailnet-query".locations."= /ready".extraConfig == getOnlyPolicy;
assert cfg.services.tempo.settings.compactor.compaction.block_retention == "168h";
assert cfg.services.loki.configuration.limits_config.retention_period == "168h";
assert !(builtins.elem 3200 cfg.networking.firewall.allowedTCPPorts);
assert !(builtins.elem 3100 cfg.networking.firewall.allowedTCPPorts);
assert !(builtins.elem 3101 cfg.networking.firewall.allowedTCPPorts);
assert builtins.length cfg.networking.firewall.interfaces.tailscale0.allowedTCPPorts == 2;
assert builtins.elem 3200 cfg.networking.firewall.interfaces.tailscale0.allowedTCPPorts;
assert builtins.elem 3101 cfg.networking.firewall.interfaces.tailscale0.allowedTCPPorts;
assert !(builtins.elem 3100 cfg.networking.firewall.interfaces.tailscale0.allowedTCPPorts);
assert cfg.systemd.services.opentelemetry-collector.serviceConfig.StateDirectoryQuota == "256M";
assert cfg.systemd.services.tempo.serviceConfig.StateDirectoryQuota == "4096M";
assert cfg.systemd.services.loki.serviceConfig.StateDirectoryQuota == "4096M";
assert builtins.elem "opentelemetry-collector.service" cfg.systemd.services.app.wants;
assert !(builtins.elem "opentelemetry-collector.service" cfg.systemd.services.app.requires);
{
  collectorReceiver = collector.receivers.otlp.protocols.http.endpoint;
  tempoExporter = collector.exporters."otlphttp/tempo".endpoint;
  lokiExporter = collector.exporters."otlphttp/loki".endpoint;
  tailnetPorts = cfg.networking.firewall.interfaces.tailscale0.allowedTCPPorts;
  lokiListenAddress = cfg.services.loki.configuration.server.http_listen_address;
  journalBodyStatement = builtins.head (builtins.head collector.processors."transform/redact_journal".log_statements).statements;
  rejectedUnsafeConfigurations = builtins.length invalidConfigurations;
  collectorSettings = collector;
  tempoSettings = cfg.services.tempo.settings;
  lokiConfiguration = cfg.services.loki.configuration;
  collectorExecStart = cfg.systemd.services.opentelemetry-collector.serviceConfig.ExecStart;
  tempoExecStart = cfg.systemd.services.tempo.serviceConfig.ExecStart;
  lokiExecStart = cfg.systemd.services.loki.serviceConfig.ExecStart;
}

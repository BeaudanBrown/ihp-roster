let
  verificationSource = import ./verification-source.nix { root = ../../..; };
  flake = builtins.getFlake (builtins.unsafeDiscardStringContext (toString verificationSource));
  lib = flake.inputs.nixpkgs.lib;
  evaluate =
    {
      pruningEnable ? true,
      serviceUser ? "ihp-roster",
      retentionDays ? 7,
      batchSize ? 1000
    }:
    lib.nixosSystem {
      system = builtins.currentSystem;
      modules = [
        flake.nixosModules.default
        ({ ... }: {
          boot.isContainer = true;
          networking.hostName = "bepis-live-outbox-pruning-check";
          services.ihpRoster = {
            enable = true;
            production = true;
            domain = "live-outbox.example.test";
            baseUrl = "https://live-outbox.example.test";
            databaseUrl = "postgresql:///live_outbox_module_check";
            inherit serviceUser;
            liveInvalidations.outboxPruning = {
              enable = pruningEnable;
              inherit retentionDays batchSize;
              onCalendar = "04:15";
              randomizedDelaySec = "30m";
            };
          };
        })
      ];
    };
  assertionsPass = evaluated: builtins.all (item: item.assertion) evaluated.config.assertions;
  enabled = evaluate { };
  disabled = evaluate { pruningEnable = false; serviceUser = null; };
  invalidConfigurations = [
    (evaluate { serviceUser = null; })
    (evaluate { retentionDays = 6; })
    (evaluate { batchSize = 1001; })
  ];
  cfg = enabled.config;
  service = cfg.systemd.services.live-invalidation-outbox-prune;
  timer = cfg.systemd.timers.live-invalidation-outbox-prune;
in
assert assertionsPass enabled;
assert assertionsPass disabled;
assert builtins.all (evaluated: !(assertionsPass evaluated)) invalidConfigurations;
assert !(builtins.hasAttr "live-invalidation-outbox-prune" disabled.config.systemd.services);
assert service.after == [ "schema-migrations-ready.service" ];
assert service.requires == [ "schema-migrations-ready.service" ];
assert service.serviceConfig.User == "ihp-roster";
assert service.serviceConfig.Type == "oneshot";
assert service.serviceConfig.NoNewPrivileges;
assert service.serviceConfig.PrivateTmp;
assert service.serviceConfig.ProtectSystem == "strict";
assert service.serviceConfig.CapabilityBoundingSet == "";
assert lib.hasSuffix "/bin/LiveInvalidationOutboxPrune" service.serviceConfig.ExecStart;
assert service.environment.LIVE_INVALIDATION_OUTBOX_RETENTION_DAYS == "7";
assert service.environment.LIVE_INVALIDATION_OUTBOX_BATCH_SIZE == "1000";
assert timer.timerConfig.OnCalendar == "04:15";
assert timer.timerConfig.Persistent;
assert timer.timerConfig.RandomizedDelaySec == "30m";
{
  enabled = true;
  disabled = true;
  retentionDays = cfg.services.ihpRoster.liveInvalidations.outboxPruning.retentionDays;
  batchSize = cfg.services.ihpRoster.liveInvalidations.outboxPruning.batchSize;
  rejectedUnsafeConfigurations = builtins.length invalidConfigurations;
}

let
  verificationSource = import ./verification-source.nix { root = ../../..; };
  flake = builtins.getFlake (builtins.unsafeDiscardStringContext (toString verificationSource));
  lib = flake.inputs.nixpkgs.lib;
  evaluate =
    refresh:
    (lib.nixosSystem {
      system = builtins.currentSystem;
      modules = [
        flake.nixosModules.default
        {
          boot.isContainer = true;
          networking.hostName = "bepis-holiday-import-check";
          services.ihpRoster = {
            enable = true;
            domain = "holiday.example.test";
            baseUrl = "https://holiday.example.test";
            databaseUrl = "postgresql:///holiday_import_check";
            environmentFile = "/run/secrets/holiday-test-env";
            enableMigrations = false;
            publicHolidays.refresh = refresh;
            additionalEnvVars.DATAVIC_ACTIVE_IMPORT = "true";
          };
        }
      ];
    }).config;
  disabled = evaluate { };
  enabled = evaluate { enable = true; };
  timer = enabled.systemd.timers.public-holiday-refresh-sweep;
  service = enabled.systemd.services.public-holiday-refresh-sweep;
in
assert !(disabled.systemd.timers ? public-holiday-refresh-sweep);
assert !(disabled.systemd.services ? public-holiday-refresh-sweep);
assert !(enabled.systemd.timers ? public-holiday-shadow-sweep);
assert timer.timerConfig.OnCalendar == "daily";
assert timer.timerConfig.RandomizedDelaySec == "30m";
assert timer.timerConfig.Persistent;
assert lib.hasSuffix "/bin/PublicHolidayRefreshSweep" service.serviceConfig.ExecStart;
assert service.environment.DATABASE_URL == "postgresql:///holiday_import_check";
assert service.environment.DATAVIC_ACTIVE_IMPORT == "true";
assert enabled.systemd.services.worker.environment.DATAVIC_ACTIVE_IMPORT == "true";
assert builtins.elem "/run/secrets/holiday-test-env"
  enabled.systemd.services.worker.serviceConfig.EnvironmentFile;
{ schedule = timer.timerConfig.OnCalendar; }

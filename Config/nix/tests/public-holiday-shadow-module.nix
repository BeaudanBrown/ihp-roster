let
  verificationSource = import ./verification-source.nix { root = ../../..; };
  flake = builtins.getFlake (builtins.unsafeDiscardStringContext (toString verificationSource));
  lib = flake.inputs.nixpkgs.lib;
  evaluate =
    shadow:
    lib.nixosSystem {
      system = builtins.currentSystem;
      modules = [
        flake.nixosModules.default
        {
          boot.isContainer = true;
          networking.hostName = "bepis-holiday-shadow-check";
          services.ihpRoster = {
            enable = true;
            domain = "shadow.example.test";
            baseUrl = "https://shadow.example.test";
            databaseUrl = "postgresql:///holiday_shadow_check";
            environmentFile = "/run/secrets/holiday-test-env";
            enableMigrations = false;
            publicHolidays.shadow = shadow;
          };
        }
      ];
    };
  disabled = (evaluate { }).config;
  enabled = (evaluate { enable = true; }).config;
  weekly =
    (evaluate {
      enable = true;
      onCalendar = "weekly";
    }).config;
  conflicting =
    ((evaluate { enable = true; }).extendModules {
      modules = [ { services.ihpRoster.publicHolidays.refresh.enable = true; } ];
    }).config;
  timer = enabled.systemd.timers.public-holiday-shadow-sweep;
  service = enabled.systemd.services.public-holiday-shadow-sweep;
in
assert !(disabled.systemd.timers ? public-holiday-shadow-sweep);
assert !(disabled.systemd.services ? public-holiday-shadow-sweep);
assert !(enabled.systemd.timers ? public-holiday-refresh-sweep);
assert !(enabled.systemd.services ? public-holiday-refresh-sweep);
assert !(conflicting.systemd.timers ? public-holiday-refresh-sweep);
assert !(conflicting.systemd.services ? public-holiday-refresh-sweep);
assert conflicting.systemd.timers ? public-holiday-shadow-sweep;
assert timer.timerConfig.OnCalendar == "daily";
assert timer.timerConfig.RandomizedDelaySec == "30m";
assert timer.timerConfig.Persistent;
assert lib.hasSuffix "/bin/PublicHolidayShadowSweep" service.serviceConfig.ExecStart;
assert service.environment.DATABASE_URL == "postgresql:///holiday_shadow_check";
assert builtins.elem "/run/secrets/holiday-test-env"
  enabled.systemd.services.worker.serviceConfig.EnvironmentFile;
assert weekly.systemd.timers.public-holiday-shadow-sweep.timerConfig.OnCalendar == "weekly";
{
  schedule = timer.timerConfig.OnCalendar;
  legacyDisabled = true;
  workerEnvironmentConfigured = true;
}

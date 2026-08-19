let
  verificationSource = import ./verification-source.nix { root = ../../..; };
  flake = builtins.getFlake (builtins.unsafeDiscardStringContext (toString verificationSource));
  lib = flake.inputs.nixpkgs.lib;
  evaluate =
    {
      enable ? true,
      onCalendar ? null,
    }:
    lib.nixosSystem {
      system = builtins.currentSystem;
      modules = [
        flake.nixosModules.default
        ({ ... }: {
          boot.isContainer = true;
          networking.hostName = "bepis-fwc-mapd-refresh-module-check";
          services.ihpRoster = {
            enable = true;
            production = true;
            domain = "fwc-mapd-refresh.example.test";
            baseUrl = "https://fwc-mapd-refresh.example.test";
            databaseUrl = "postgresql:///fwc_mapd_refresh_module_check";
            enableMigrations = false;
            fwcMapd.refresh = {
              inherit enable;
              randomizedDelaySec = "2h";
            }
            // lib.optionalAttrs (onCalendar != null) { inherit onCalendar; };
          };
        })
      ];
    };
  defaults = evaluate { };
  disabled = evaluate { enable = false; };
  overridden = evaluate { onCalendar = "Wed *-*-* 01:00:00"; };
  defaultCfg = defaults.config;
  defaultTimer = defaultCfg.systemd.timers.fwc-mapd-refresh-sweep;
  defaultService = defaultCfg.systemd.services.fwc-mapd-refresh-sweep;
in
assert defaultCfg.services.ihpRoster.fwcMapd.refresh.onCalendar == "Sun *-*-* 03:00:00";
assert defaultTimer.timerConfig.OnCalendar == "Sun *-*-* 03:00:00";
assert defaultTimer.timerConfig.Persistent;
assert defaultTimer.timerConfig.RandomizedDelaySec == "2h";
assert builtins.elem "timers.target" defaultTimer.wantedBy;
assert lib.hasSuffix "/bin/FwcMapdRefreshSweep" defaultService.serviceConfig.ExecStart;
assert !(disabled.config.systemd.timers ? fwc-mapd-refresh-sweep);
assert !(disabled.config.systemd.services ? fwc-mapd-refresh-sweep);
assert
  overridden.config.systemd.timers.fwc-mapd-refresh-sweep.timerConfig.OnCalendar
  == "Wed *-*-* 01:00:00";
{
  defaultOnCalendar = defaultTimer.timerConfig.OnCalendar;
  persistent = defaultTimer.timerConfig.Persistent;
  randomizedDelaySec = defaultTimer.timerConfig.RandomizedDelaySec;
}

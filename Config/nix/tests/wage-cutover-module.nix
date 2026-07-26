let
  flake = builtins.getFlake (toString ../../..);
  lib = flake.inputs.nixpkgs.lib;
  evaluated = lib.nixosSystem {
    system = builtins.currentSystem;
    modules = [
      flake.nixosModules.default
      ({ ... }: {
        boot.isContainer = true;
        networking.hostName = "bepis-wage-cutover-module-check";
        services.ihpRoster = {
          enable = true;
          production = true;
          domain = "wage-cutover.example.test";
          baseUrl = "https://wage-cutover.example.test";
          databaseUrl = "postgresql:///wage_cutover_module_check";
          enableMigrations = true;
        };
      })
    ];
  };
  cfg = evaluated.config;
  cutover = cfg.systemd.services.wage-cutover;
in
assert builtins.elem "migrate.service" cutover.after;
assert builtins.elem "migrate.service" cutover.requires;
assert cutover.serviceConfig.Type == "oneshot";
assert builtins.elem "wage-cutover.service" cfg.systemd.services.app.after;
assert builtins.elem "wage-cutover.service" cfg.systemd.services.app.requires;
assert lib.hasInfix "/bin/BackfillTimesheetPayLedger" cutover.script;
assert lib.hasInfix "retire-legacy-wage-calculators.sql" cutover.script;
assert cutover.environment.DEFAULT_DATABASE_URL == "postgresql:///wage_cutover_module_check";
true

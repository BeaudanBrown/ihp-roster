let
  verificationSource = import ./verification-source.nix { root = ../../..; };
  flake = builtins.getFlake (builtins.unsafeDiscardStringContext (toString verificationSource));
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
  schemaReady = cfg.systemd.services.schema-migrations-ready;
in
assert builtins.elem "migrate.service" cutover.after;
assert builtins.elem "migrate.service" cutover.requires;
assert cutover.serviceConfig.Type == "oneshot";
assert builtins.elem "schema-migrations-ready.service" cutover.before;
assert builtins.elem "wage-cutover.service" schemaReady.after;
assert builtins.elem "wage-cutover.service" schemaReady.requires;
assert schemaReady.serviceConfig.Type == "oneshot";
assert builtins.elem "schema-migrations-ready.service" cfg.systemd.services.app.after;
assert builtins.elem "schema-migrations-ready.service" cfg.systemd.services.app.requires;
assert builtins.elem "schema-migrations-ready.service" cfg.systemd.services.worker.after;
assert builtins.elem "schema-migrations-ready.service" cfg.systemd.services.worker.requires;
assert lib.hasInfix "SELECT revision FROM schema_migrations" schemaReady.script;
assert lib.hasInfix "Refusing to start ihp-roster" schemaReady.script;
assert lib.hasInfix "/bin/BackfillTimesheetPayLedger" cutover.script;
assert lib.hasInfix "retire-legacy-wage-calculators.sql" cutover.script;
assert cutover.environment.DEFAULT_DATABASE_URL == "postgresql:///wage_cutover_module_check";
assert schemaReady.environment.DEFAULT_DATABASE_URL == "postgresql:///wage_cutover_module_check";
true

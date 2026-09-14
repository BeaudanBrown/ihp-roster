let
  repoRoot = builtins.unsafeDiscardStringContext (toString ../../..);
  # Use the same Git-flake source semantics as production: tracked dirty edits
  # participate, while untracked working-tree artifacts do not.
  flake = builtins.getFlake "git+file://${repoRoot}";
  evaluated = flake.inputs.nixpkgs.lib.nixosSystem {
    system = builtins.currentSystem;
    modules = [
      flake.nixosModules.default
      ({ ... }: {
        boot.isContainer = true;
        networking.hostName = "bepis-production-source-check";
        system.stateVersion = "25.05";
        services.ihpRoster = {
          enable = true;
          production = true;
          domain = "source-boundary.example.test";
          baseUrl = "https://source-boundary.example.test";
          databaseUrl = "postgresql:///source_boundary_check";
          enableMigrations = true;
        };
      })
    ];
  };
in
evaluated.config.system.build.toplevel.drvPath

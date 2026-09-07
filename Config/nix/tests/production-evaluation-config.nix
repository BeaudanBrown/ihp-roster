# Evaluation only: the checked-in production hardware file is a placeholder.
# Never import this fixture from a host or deployment output.
let
  repoRoot = builtins.unsafeDiscardStringContext (toString ../../..);
  flake = builtins.getFlake "git+file://${repoRoot}";
  evaluated = flake.nixosConfigurations.production.extendModules {
    modules = [ {
      # Supply only missing hardware identity. Retain production mount options
      # (including prjquota), services and assertions for verification.
      fileSystems."/".fsType = "ext4";
    } ];
  };
in
evaluated.config

{ ... }:
{
    perSystem = { pkgs, ... }:
        let
            projectSource = import ./project-source.nix { inherit pkgs; };
        in
        {
            ihp = {
                appName = "app"; # Change this to your project name
                enable = true;
                withHoogle = true;
                # Use a filtered project source so local dev artifacts do not leak into
                # production packaging or generated app-lib.cabal module discovery.
                projectPath = projectSource;
                packages = with pkgs; [
                    poppler-utils
                ];
                haskellPackages = p:
                    let
                        webauthn = pkgs.haskell.lib.doJailbreak (p.callHackageDirect {
                            pkg = "webauthn";
                            ver = "0.11.0.0";
                            sha256 = "sha256-iJygaLPu0NyOHxUKwpd7vMkUnIXNRtAnnCumqKqces8=";
                        } {});
                    in with p; [
                        # Haskell dependencies go here
                        aeson
                        p.ihp
                        p.ihp-mail
                        p.ihp-hspec
                        base64-bytestring
                        base
                        crypton
                        hourglass
                        http-conduit
                        ip
                        postgresql-simple
                        process
                        validation
                        wai
                        webauthn
                        text
                        zip-archive
                        hspec
                    ];
                devHaskellPackages = p: with p; [
                    hlint
                    stylish-haskell
                ];
            };
        };
}

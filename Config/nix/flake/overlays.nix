[
    (final: prev: {
        ghc = prev.ghc.extend (hfinal: hprev: {
            ihp-ide = prev.haskell.lib.overrideCabal hprev.ihp-ide (old: {
                postPatch = (old.postPatch or "") + ''
                    substituteInPlace IHP/IDE/PortConfig.hs \
                        --replace "Socket.tupleToHostAddress (127, 0, 0, 1)" "Socket.tupleToHostAddress (0, 0, 0, 0)"
                '';
            });
        });

        stripe-cli =
            let
                version = "1.42.10";
                assets = {
                    x86_64-linux = {
                        platform = "linux_x86_64";
                        hash = "sha256-BHLeW7aGtPvTcYdP2hWmy5hVN1Wg0oHX2sp10Hz80/I=";
                    };
                };
                asset = assets.${final.stdenv.hostPlatform.system} or null;
            in
                if asset == null then
                    prev.stripe-cli
                else
                    final.stdenv.mkDerivation {
                        pname = "stripe-cli";
                        inherit version;
                        src = final.fetchurl {
                            url = "https://github.com/stripe/stripe-cli/releases/download/v${version}/stripe_${version}_${asset.platform}.tar.gz";
                            inherit (asset) hash;
                        };
                        sourceRoot = ".";
                        dontBuild = true;
                        nativeBuildInputs = [ final.installShellFiles ];
                        installPhase = ''
                            runHook preInstall
                            install -Dm755 stripe $out/bin/stripe
                            installShellCompletion --cmd stripe \
                                --bash <($out/bin/stripe completion --write-to-stdout --shell bash) \
                                --zsh <($out/bin/stripe completion --write-to-stdout --shell zsh)
                            runHook postInstall
                        '';
                        meta = prev.stripe-cli.meta // {
                            homepage = "https://stripe.com/docs/stripe-cli";
                            changelog = "https://github.com/stripe/stripe-cli/releases/tag/v${version}";
                            mainProgram = "stripe";
                        };
                    };
    })
]

[
    (final: prev: {
        ghc = prev.ghc.extend (hfinal: hprev: {
            ihp-ide = prev.haskell.lib.overrideCabal hprev.ihp-ide (old: {
                postPatch = (old.postPatch or "") + ''
                    substituteInPlace IHP/IDE/PortConfig.hs \
                        --replace-fail "Socket.tupleToHostAddress (127, 0, 0, 1)" "Socket.tupleToHostAddress (0, 0, 0, 0)" \
                        --replace-fail 'envAppPort :: Maybe Socket.PortNumber' 'envAppPort :: Maybe Int' \
                        --replace-fail '        Just appPort -> pure PortConfig { appPort = appPort, toolServerPort = appPort + 1 }' $'        Just port\n            | port > 0 && port < 65535 -> do\n                let portConfig = PortConfig { appPort = fromIntegral port, toolServerPort = fromIntegral (port + 1) }\n                available <- isPortConfigAvailable portConfig\n                unless available do\n                    error ("Configured PORT requires both " <> show port <> " and " <> show (port + 1) <> " to be available")\n                pure portConfig\n        Just port -> error ("Configured PORT is outside the valid TCP range: " <> show port)'
                '';
            });

            # The published hs-opentelemetry-instrumentation-wai-0.1.1.0 Cabal
            # file still bounds hs-opentelemetry-api ==0.2.*, while nixpkgs
            # ships hs-opentelemetry-api-0.3.0.0. The source builds against
            # 0.3.0.0 with the stale bound removed, so keep this local
            # jailbreak until nixpkgs/Hackage carries a compatible release.
            hs-opentelemetry-instrumentation-wai =
                prev.haskell.lib.markUnbroken (
                    prev.haskell.lib.overrideCabal
                        (prev.haskell.lib.doJailbreak hprev.hs-opentelemetry-instrumentation-wai)
                        (old: {
                            postPatch = (old.postPatch or "") + ''
                                substituteInPlace src/OpenTelemetry/Instrumentation/Wai.hs \
                                    --replace-fail '("url.query", toAttribute $ T.decodeUtf8 $ rawQueryString req)' \
                                              '("bepis.http.query_redacted", toAttribute True)' \
                                    --replace-fail '("http.target", toAttribute $ T.decodeUtf8 (rawPathInfo req <> rawQueryString req))' \
                                              '("http.target", toAttribute $ T.decodeUtf8 (rawPathInfo req))'
                            '';
                        })
                );
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

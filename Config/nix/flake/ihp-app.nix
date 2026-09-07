{ inputs, ... }:
{
    perSystem = { config, inputs', lib, pkgs, ... }:
        let
            productionProjectSource = import ./project-source.nix { inherit pkgs; };
            frontendContractToolSource = import ./frontend-contract-tool-source.nix { inherit pkgs; };
            ihpSource = inputs.ihp.outPath;
            productionNixSupport = import ./production-nix-support.nix { inherit lib; ihp = ihpSource; };
            frontendContractToolGhc = pkgs.ghc.ghcWithPackages (p:
                config.ihp.haskellPackages p ++ [ p.ihp-ide p.ihp-schema-compiler ]
            );
            productionServer = optimized: import productionNixSupport {
                ihp = ihpSource;
                haskellDeps = config.ihp.haskellPackages;
                otherDeps = _: config.ihp.packages;
                projectPath = config.ihp.projectPath;
                inherit optimized pkgs;
                ghc = pkgs.ghc;
                rtsFlags = config.ihp.rtsFlags;
                optimizationLevel = if optimized then config.ihp.optimizationLevel else "0";
                relationSupport = config.ihp.relationSupport;
                appName = config.ihp.appName;
                filter = inputs.ihp.inputs.nix-filter.lib;
                ihp-env-var-backwards-compat = inputs'.ihp.packages.ihp-env-var-backwards-compat;
                ihp-static = inputs'.ihp.packages.ihp-static;
                static = config.packages.static;
            };
            # Reviewed compatibility package: deployed timers and recovery commands
            # retain their existing paths while upstream builds scripts independently.
            productionApp = optimized:
                let
                    server = productionServer optimized;
                    scripts = lib.mapAttrs (name: binary: pkgs.runCommand "bepis-script-${name}" {
                        nativeBuildInputs = [ pkgs.makeWrapper ];
                    } ''
                        makeWrapper ${binary}/bin/${name} $out/bin/${name} \
                            --set-default APP_STATIC ${config.packages.static} \
                            --set-default IHP_STATIC ${inputs'.ihp.packages.ihp-static} \
                            --prefix PATH : ${lib.makeBinPath config.ihp.packages}
                    '') server.scriptBinaries;
                in pkgs.symlinkJoin {
                    name = "bepis-production-compat";
                    paths = [ server ] ++ builtins.attrValues scripts;
                    passthru = server.passthru // { scriptBinaries = scripts; };
                };
            optimizedApp = productionApp true;
            unoptimizedApp = productionApp false;
            scriptOutputs = if config.ihp.scripts.optimized then optimizedApp.scriptBinaries else unoptimizedApp.scriptBinaries;
        in
        {
            imports = [ {
                # Upstream closes over its own NixSupport import rather than the
                # overridden server output. Force scripts through the managed seam.
                packages = lib.mapAttrs' (name: binary:
                    lib.nameValuePair "script-${name}" (lib.mkForce binary)
                ) scriptOutputs;
                apps = lib.mapAttrs' (name: binary:
                    lib.nameValuePair "script-${name}" (lib.mkForce {
                        type = "app";
                        program = "${binary}/bin/${name}";
                    })
                ) scriptOutputs;
            } ];
            ihp = {
                appName = "app";
                enable = true;
                withHoogle = true;
                # Use a filtered project source so local dev artifacts do not leak into
                # production packaging or generated app-lib.cabal module discovery.
                projectPath = productionProjectSource;
                # Bepis loads split static assets directly from Web.View.Layout via
                # assetPath. Disable IHP's optional prod.js/prod.css concatenation so
                # production packaging does not generate unused bundle artifacts.
                static.makeBundling = false;
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
                        aeson
                        p.ihp
                        p.ihp-mail
                        base64-bytestring
                        base
                        crypton
                        hourglass
                        hasql
                        hs-opentelemetry-api
                        hs-opentelemetry-exporter-otlp
                        hs-opentelemetry-instrumentation-wai
                        hs-opentelemetry-propagator-w3c
                        hs-opentelemetry-sdk
                        http-conduit
                        ip
                        postgresql-simple
                        process
                        tz
                        validation
                        wai
                        webauthn
                        text
                        xlsx
                        xml-conduit
                        zip-archive
                    ];
                devHaskellPackages = p: with p; [
                    hspec
                    ihp-hspec
                    QuickCheck
                    hlint
                    stylish-haskell
                ];
            };

            packages.bepis-tempo = (import inputs.nixpkgs-tempo {
                system = pkgs.stdenv.hostPlatform.system;
            }).tempo;
            packages.optimized-prod-server = lib.mkForce optimizedApp;
            packages.unoptimized-prod-server = lib.mkForce unoptimizedApp;
            # IHP's default schema derivation takes the complete projectPath as
            # src even though it installs only Schema.sql. Keep schema cache
            # ownership on the authoritative file itself.
            packages.schema = lib.mkForce (pkgs.runCommand "schema" { } ''
                mkdir "$out"
                cp ${../../../Application/Schema.sql} "$out/Schema.sql"
            '');

            packages.frontend-contract-tools = pkgs.stdenv.mkDerivation {
                name = "bepis-frontend-contract-tools";
                src = frontendContractToolSource;
                nativeBuildInputs = [ frontendContractToolGhc pkgs.gnumake pkgs.time ];
                buildPhase = ''
                    runHook preBuild
                    IHP_DATA="$(ghc-pkg field ihp-ide data-dir --simple-output)"
                    export IHP="$IHP_DATA/lib/IHP"
                    export IHP_LIB="$IHP_DATA"
                    make build/Generated/Types.hs
                    GHC_OPTIONS="$(make print-ghc-options GHC_RTS_FLAGS= | sed 's/-iIHP[^ ]* //g; s/-fbyte-code//g')"
                    mkdir -p build/frontend-contract-tools/bin build/frontend-contract-tools/obj build/frontend-contract-tools/hi
                    while IFS='|' read -r module binary; do
                        ${pkgs.time}/bin/time -v -a -o build/frontend-contract-tools/build-time.txt \
                            ghc -j"''${NIX_BUILD_CORES:-1}" $GHC_OPTIONS \
                            "$module.hs" -main-is "''${module//\//.}" \
                            -odir build/frontend-contract-tools/obj \
                            -hidir build/frontend-contract-tools/hi \
                            -o "build/frontend-contract-tools/bin/$binary"
                    done <<'TOOLS'
Application/Script/GenerateFrontendContracts|generate-frontend-contracts
Application/Script/GenerateFrontendSurfaceAdapters|generate-frontend-surface-adapters
Application/Script/GenerateBepisArchitectureContracts|generate-bepis-architecture-contracts
TOOLS
                    runHook postBuild
                '';
                installPhase = ''
                    mkdir -p "$out/bin" "$out/share/frontend-contract-tools"
                    cp build/frontend-contract-tools/bin/* "$out/bin/"
                    cp build/frontend-contract-tools/build-time.txt "$out/share/frontend-contract-tools/"
                    interface_count="$(find build/frontend-contract-tools/hi -type f -name '*.hi' | wc -l)"
                    interface_bytes="$(find build/frontend-contract-tools/hi -type f -name '*.hi' -printf '%s\n' | awk '{ total += $1 } END { print total + 0 }')"
                    dynamic_interface_count="$(find build/frontend-contract-tools/hi -type f -name '*.dyn_hi' | wc -l)"
                    dynamic_interface_bytes="$(find build/frontend-contract-tools/hi -type f -name '*.dyn_hi' -printf '%s\n' | awk '{ total += $1 } END { print total + 0 }')"
                    largest_interface="$(find build/frontend-contract-tools/hi -type f \( -name '*.hi' -o -name '*.dyn_hi' \) -printf '%s\t%P\n' | awk -F '\t' '$1 > largest { largest = $1; path = $2 } END { print largest "\t" path }')"
                    printf 'metric\tbytes_or_count\tpath\ninterface_count\t%s\t-\ninterface_bytes\t%s\t-\ndynamic_interface_count\t%s\t-\ndynamic_interface_bytes\t%s\t-\nlargest_interface\t%s\n' \
                        "$interface_count" "$interface_bytes" "$dynamic_interface_count" "$dynamic_interface_bytes" "$largest_interface" \
                        > "$out/share/frontend-contract-tools/build-metrics.tsv"
                '';
                enableParallelBuilding = true;
            };
        };
}

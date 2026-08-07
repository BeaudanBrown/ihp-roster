{ ... }:
{
    perSystem = { config, pkgs, ... }:
        let
            projectSource = import ./project-source.nix { inherit pkgs; };
            frontendContractToolSource = import ./frontend-contract-tool-source.nix { inherit pkgs; };
            frontendContractToolGhc = pkgs.ghc.ghcWithPackages (p:
                config.ihp.haskellPackages p ++ [ p.ihp-ide p.ihp-schema-compiler ]
            );
        in
        {
            ihp = {
                appName = "app";
                enable = true;
                withHoogle = true;
                # Use a filtered project source so local dev artifacts do not leak into
                # production packaging or generated app-lib.cabal module discovery.
                projectPath = projectSource;
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
                        p.ihp-hspec
                        base64-bytestring
                        base
                        crypton
                        hourglass
                        hs-opentelemetry-api
                        hs-opentelemetry-exporter-otlp
                        hs-opentelemetry-instrumentation-wai
                        hs-opentelemetry-propagator-w3c
                        hs-opentelemetry-sdk
                        http-conduit
                        ip
                        postgresql-simple
                        process
                        QuickCheck
                        tz
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

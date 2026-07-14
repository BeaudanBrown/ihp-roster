{ inputs, ... }:
{
    perSystem = { system, lib, ... }:
        let
            supported = system == "x86_64-linux";
            androidPkgs = import inputs.nixpkgs {
                inherit system;
                config = {
                    # The emulator and Google Play image are unfree. Keep this
                    # acceptance isolated from normal app and development packages.
                    allowUnfree = true;
                    android_sdk.accept_license = true;
                };
            };
            sdkArgs = {
                platformVersions = [ "35" ];
                buildToolsVersions = [ ];
                cmdLineToolsVersion = "8.0";
                includeCmake = false;
                includeEmulator = true;
                includeSystemImages = true;
                systemImageTypes = [ "google_apis_playstore" ];
                abiVersions = [ "x86_64" ];
            };
            androidComposition = androidPkgs.androidenv.composeAndroidPackages sdkArgs;
            deviceName = "bepis-pwa";
            androidEmulator = androidPkgs.androidenv.emulateApp {
                name = "bepis-pwa-android-emulator";
                platformVersion = "35";
                abiVersion = "x86_64";
                systemImageType = "google_apis_playstore";
                inherit deviceName;
                androidUserHome = ".devenv/android";
                androidAvdHome = ".devenv/android/avd";
                sdkExtraArgs = sdkArgs;
                configOptions = {
                    "hw.keyboard" = "yes";
                    "hw.gpu.enabled" = "yes";
                    "hw.gpu.mode" = "auto";
                };
            };
            adb = "${androidComposition.androidsdk}/libexec/android-sdk/platform-tools/adb";
            installUrl = "http://localhost:8000/InstallApp";
            launcherScript = builtins.replaceStrings
                [ "@adb@" "@androidEmulator@" "@installUrl@" "@deviceName@" ]
                [ adb "${androidEmulator}" installUrl deviceName ]
                (builtins.readFile ../scripts/pwa/android-emulator);
            launcher = androidPkgs.writeShellApplication {
                name = "bepis-pwa-android";
                runtimeInputs = [
                    androidPkgs.coreutils
                    androidPkgs.curl
                    androidPkgs.gawk
                    androidPkgs.gnugrep
                ];
                text = launcherScript;
            };
        in
        lib.optionalAttrs supported {
            apps.bepis-pwa-android = {
                type = "app";
                program = "${launcher}/bin/bepis-pwa-android";
            };
        };
}

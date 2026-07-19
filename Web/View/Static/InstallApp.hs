module Web.View.Static.InstallApp where

import Application.Helper.FrontendContract.PwaInstall.Runtime
import Web.View.Prelude

data InstallAppView = InstallAppView

instance View InstallAppView where
    html InstallAppView = [hsx|
        <div class="app-public-page" {...pwaInstallPageAttrs}>
            <section class="app-public-section">
                <p class="app-public-kicker">Bepis on your device</p>
                <h1>Install Bepis</h1>
                <p>
                    Add Bepis to your home screen for quick access. Bepis still requires an internet connection and does not store venue data for offline use.
                </p>
                <div class="alert alert-success mt-4 mb-0" role="status" {...pwaInstalledStatusAttrs} hidden="hidden">
                    Bepis is installed on this device.
                </div>
            </section>

            <section class="app-public-section" aria-labelledby="install-bepis-android">
                <h2 id="install-bepis-android">Android</h2>
                <p>
                    When your browser supports direct installation, use the button below. Otherwise, open the browser menu and choose <strong>Install app</strong> or <strong>Add to Home screen</strong>.
                </p>
                <button class="btn btn-primary" type="button" {...pwaInstallButtonAttrs} hidden="hidden">
                    Install Bepis
                </button>
                <p class="mt-3 mb-0" role="status" aria-live="polite" {...pwaInstallResultAttrs}>
                    <span {...pwaInstallResultStateAttrs PwaInstallAccepted} hidden="hidden">
                        Installation accepted. Bepis will appear on your device when installation completes.
                    </span>
                    <span {...pwaInstallResultStateAttrs PwaInstallDismissed} hidden="hidden">
                        Installation was not completed. You can use the browser menu to try again.
                    </span>
                    <span {...pwaInstallResultStateAttrs PwaInstallFailed} hidden="hidden">
                        Installation could not start. Use the browser menu to install Bepis.
                    </span>
                </p>
            </section>

            <section class="app-public-section" aria-labelledby="install-bepis-apple">
                <h2 id="install-bepis-apple">iPhone and iPad</h2>
                <ol class="mb-0">
                    <li>Open Bepis in Safari.</li>
                    <li>Tap the <strong>Share</strong> button.</li>
                    <li>Select <strong>Add to Home Screen</strong>.</li>
                    <li>Enable <strong>Open as Web App</strong> if that option is shown.</li>
                    <li>Tap <strong>Add</strong>.</li>
                </ol>
            </section>
        </div>
    |]

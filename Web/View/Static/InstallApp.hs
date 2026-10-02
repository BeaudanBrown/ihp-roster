module Web.View.Static.InstallApp where

import Application.Helper.FrontendContract.PwaInstall.Runtime
import Web.View.Prelude

data InstallAppView = InstallAppView

instance View InstallAppView where
    html InstallAppView = [hsx|
        <div class="app-page-auth" {...pwaInstallPageAttrs}>
            <section class="app-auth-card app-auth-card-wide">
                <div class="app-auth-body">
                    <h1>Install Bepis</h1>
                    <p>Open Bepis straight from your home screen or desktop.</p>
                    <p class="app-muted small">Internet required. You can also use Bepis in your browser.</p>
                    <a href={WelcomeAction} {...pwaInstallHomeAttrs} hidden="hidden">Home</a>
                    <p role="status" {...pwaInstalledStatusAttrs} hidden="hidden">Installation complete. You can now open Bepis from your home screen or desktop.</p>
                    <button class="btn btn-primary w-100" type="button" {...pwaInstallButtonAttrs} hidden="hidden">Install Bepis</button>
                    <p class="mt-3" role="status" aria-live="polite" {...pwaInstallResultAttrs}>
                        <span {...pwaInstallResultStateAttrs PwaInstallAccepted} hidden="hidden">Installation accepted. Bepis will appear on your device when installation completes.</span>
                        <span {...pwaInstallResultStateAttrs PwaInstallDismissed} hidden="hidden">Installation was not completed. You can use the browser menu to try again.</span>
                        <span {...pwaInstallResultStateAttrs PwaInstallFailed} hidden="hidden">Installation could not start. Use the browser menu to install Bepis.</span>
                    </p>
                    <details open="open" {...pwaInstallManualAttrs}>
                        <summary>Install another way</summary>
                        <details class="my-3" {...pwaInstallChooserAttrs} hidden="hidden">
                            <summary>Choose another device</summary>
                            <label class="form-label mt-2" for="install-device">Device</label>
                            <select class="form-select" id="install-device" {...pwaInstallChooserAttrs}>
                                {deviceOption GeneralGuide "Choose a device"}
                                {deviceOption IosGuide "iPhone / iPad"}
                                {deviceOption AndroidGuide "Android"}
                                {deviceOption WindowsGuide "Windows"}
                                {deviceOption MacGuide "Mac"}
                                {deviceOption LinuxGuide "Linux"}
                            </select>
                        </details>
                        <section {...pwaInstallGuidePanelAttrs IosGuide}>
                            <h2 class="h5">iPhone and iPad</h2>
                            <ol><li>Open Bepis in Safari.</li><li>Tap <strong>Share</strong>, then <strong>Add to Home Screen</strong>.</li><li>Enable <strong>Open as Web App</strong> if shown, then tap <strong>Add</strong>.</li></ol>
                        </section>
                        <section {...pwaInstallGuidePanelAttrs AndroidGuide}>
                            <h2 class="h5">Android</h2>
                            <ol><li>Open Bepis in Chrome or Edge.</li><li>Open the browser menu and choose <strong>Install app</strong> or <strong>Add to Home screen</strong>.</li><li>Follow the browser's confirmation steps.</li></ol>
                        </section>
                        <section {...pwaInstallGuidePanelAttrs WindowsGuide}>
                            <h2 class="h5">Windows</h2>
                            <p>Install with Chrome or Edge. Firefox 143 or newer also supports web apps on Windows (Microsoft Store installations require Firefox 150 or newer).</p>
                        </section>
                        <section {...pwaInstallGuidePanelAttrs MacGuide}>
                            <h2 class="h5">Mac</h2>
                            <p>Install with Chrome or Edge, or use Safari on macOS Sonoma 14 or newer.</p>
                        </section>
                        <section {...pwaInstallGuidePanelAttrs LinuxGuide}>
                            <h2 class="h5">Linux</h2>
                            <p>Install with Chrome or Edge. Desktop integration varies. Firefox does not provide built-in web-app installation on Linux.</p>
                        </section>
                        <p {...pwaInstallGuidePanelAttrs ChromeGuide}>In Chrome, open the menu, then <strong>Cast, save, and share</strong> → <strong>Install page as app</strong>, and confirm.</p>
                        <p {...pwaInstallGuidePanelAttrs EdgeGuide}>In Edge, open the menu, then <strong>More tools</strong> → <strong>Apps</strong> → <strong>Install this site as an app</strong>, and confirm.</p>
                        <p {...pwaInstallGuidePanelAttrs SafariGuide}>In Safari on macOS Sonoma 14 or newer, choose <strong>File</strong> → <strong>Add to Dock</strong>, then <strong>Add</strong>.</p>
                        <p {...pwaInstallGuidePanelAttrs FirefoxGuide}>In supported Firefox versions on Windows, click the web-app button in the address bar and confirm.</p>
                        <p {...pwaInstallGuidePanelAttrs GeneralGuide}>Choose your device for instructions. If your browser does not offer installation, open Bepis in a supported browser listed above. Installation is optional; you can keep using Bepis in your browser.</p>
                    </details>
                </div>
            </section>
        </div>
    |]

deviceOption :: PwaInstallGuide -> Text -> Html
deviceOption guide label = [hsx|<option value={pwaInstallGuideValue guide}>{label}</option>|]

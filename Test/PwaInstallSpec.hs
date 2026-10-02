module Test.PwaInstallSpec where

import Application.Helper.FrontendContract.PwaInstall.Runtime
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "PWA install contract runtime" do
    it "renders guide choices and global install roles from the contract" do
        pwaInstallLinkAttrs `shouldBe` [("data-bepis-pwa-install-link", "true")]
        pwaInstallHomeAttrs `shouldBe` [("data-bepis-pwa-install-home", "true")]
        pwaInstallManualAttrs `shouldBe` [("data-bepis-pwa-install-manual", "true")]
        pwaInstallChooserAttrs `shouldBe` [("data-bepis-pwa-install-chooser", "true")]
        map pwaInstallGuideValue [IosGuide, AndroidGuide, WindowsGuide, MacGuide, LinuxGuide, ChromeGuide, EdgeGuide, SafariGuide, FirefoxGuide, GeneralGuide]
            `shouldBe` ["ios", "android", "windows", "mac", "linux", "chrome", "edge", "safari", "firefox", "general"]
        pwaInstallGuidePanelAttrs IosGuide `shouldBe` [("data-bepis-pwa-install-guide-panel", "ios")]
    it "renders generated roles and closed result states" do
        pwaInstallPageAttrs
            `shouldBe` [("data-bepis-pwa-install-page", "true")]
        pwaInstallButtonAttrs
            `shouldBe` [("data-bepis-pwa-install-button", "true")]
        pwaInstallResultAttrs
            `shouldBe` [("data-bepis-pwa-install-result", "true")]
        pwaInstalledStatusAttrs
            `shouldBe` [("data-bepis-pwa-installed-status", "true")]
        fmap pwaInstallResultStateAttrs
            [ PwaInstallAccepted
            , PwaInstallDismissed
            , PwaInstallFailed
            ]
            `shouldBe`
                [ [("data-bepis-pwa-install-result-state", "accepted")]
                , [("data-bepis-pwa-install-result-state", "dismissed")]
                , [("data-bepis-pwa-install-result-state", "failed")]
                ]

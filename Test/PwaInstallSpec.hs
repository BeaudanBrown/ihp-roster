module Test.PwaInstallSpec where

import Application.Helper.FrontendContract.PwaInstall.Runtime
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "PWA install contract runtime" do
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

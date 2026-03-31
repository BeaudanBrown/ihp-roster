module Test.LiveUpdateSpec where

import Application.Helper.LiveUpdate
import qualified Data.Aeson as Aeson
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "LiveUpdate runtime" do
    it "round-trips commands, fragments, and messages through JSON" do
        let command =
                SubscribeLiveUpdates
                    { scope = "dashboard-live-demo"
                    , clientId = "client-1"
                    , lastSeenVersion = Just 3
                    }
        let fragment =
                LiveFragmentRef
                    { targetId = "dashboard-live-demo-fragment"
                    , url = "/ShowDashboardLiveDemoContent"
                    , deferUntilBlur = False
                    }
        let message =
                LiveUpdatesInvalidated
                    { scope = "dashboard-live-demo"
                    , version = 4
                    , fragments = [fragment]
                    , sourceClientId = Just "client-1"
                    }

        Aeson.decode (Aeson.encode command) `shouldBe` Just command
        Aeson.decode (Aeson.encode fragment) `shouldBe` Just fragment
        Aeson.decode (Aeson.encode message) `shouldBe` Just message

    it "increments the scope version when broadcasting invalidations" do
        let scope = "test-live-update-version"
        let fragment =
                LiveFragmentRef
                    { targetId = "fragment"
                    , url = "/fragment"
                    , deferUntilBlur = False
                    }

        resetLiveUpdateScope scope
        currentLiveUpdateVersion scope `shouldReturn` 0

        broadcastLiveInvalidation scope [fragment] Nothing

        currentLiveUpdateVersion scope `shouldReturn` 1

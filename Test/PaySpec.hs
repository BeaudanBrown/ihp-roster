module Test.PaySpec where

import Application.Helper.Pay
import Data.Time.Calendar (fromGregorian)
import IHP.Prelude
import Test.Hspec

-- Non-calculation pay-version/date helpers remain here. Wage arithmetic and
-- approved-ledger contracts live in the focused WageEngine/export suites.
tests :: Spec
tests =
    describe "Pay helper orchestration" do
        it "derives venue-effective award dates from the next venue week boundary" do
            venueEffectiveRateDate 1 (fromGregorian 2026 7 1) `shouldBe` fromGregorian 2026 7 6
            venueEffectiveRateDate 1 (fromGregorian 2026 7 6) `shouldBe` fromGregorian 2026 7 6
            venueEffectiveRateEndDate 1 (Just (fromGregorian 2026 6 30)) `shouldBe` Just (fromGregorian 2026 7 5)

        it "collapses deterministic pay-version manifests" do
            collapsePayVersionManifests [] `shouldBe` Nothing
            collapsePayVersionManifests ["staff:a;shift:b"] `shouldBe` Just "staff:a;shift:b"
            collapsePayVersionManifests ["staff:b;shift:c", "staff:a;shift:b"]
                `shouldBe` Just "staff:b;shift:c | staff:a;shift:b"

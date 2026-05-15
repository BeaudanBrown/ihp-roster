module Test.Controller.SupportSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import Config
import IHP.FrameworkConfig
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Test.Hspec
import Test.Support
import Web.Controller.Support ()
import Web.FrontController ()
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "SupportController" do
        it "redirects unauthenticated users from live support fragments" $ withContext do
            response <- callAction ShowFwcMapdAwardRatesSectionAction

            response `responseStatusShouldBe` status302

        it "redirects ordinary users from live support fragments" $ withContext do
            withCleanDb do
                user <- createUserRecord "support-fragment-user@example.com" "staff" True

                response <- withPasskeyVerifiedUser user do
                    callAction ShowPublicHolidaysSectionAction

                response `responseStatusShouldBe` status302

        it "serves live support fragments to super admins through the surface rule" $ withContext do
            withCleanDb do
                superAdmin <- createUserRecordWithPlatformRole "support-fragment-super@example.com" "staff" (Just SuperAdminRole) True

                awardRatesResponse <- withPasskeyVerifiedUser superAdmin do
                    callAction ShowFwcMapdAwardRatesSectionAction
                publicHolidaysResponse <- withPasskeyVerifiedUser superAdmin do
                    callAction ShowPublicHolidaysSectionAction

                awardRatesResponse `responseStatusShouldBe` status200
                awardRatesResponse `responseBodyShouldContain` "id=\"support-award-rates-section\""
                awardRatesResponse `responseBodyShouldNotContain` "id=\"app\""
                publicHolidaysResponse `responseStatusShouldBe` status200
                publicHolidaysResponse `responseBodyShouldContain` "id=\"support-public-holidays-section\""
                publicHolidaysResponse `responseBodyShouldNotContain` "id=\"app\""

        it "mounts support live surface metadata for super admins" $ withContext do
            withCleanDb do
                superAdmin <- createUserRecordWithPlatformRole "support-surface-super@example.com" "staff" (Just SuperAdminRole) True

                response <- withPasskeyVerifiedUser superAdmin do
                    callAction SupportAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-live-update-surface=\""
                response `responseBodyShouldContain` "support_platform"
                response `responseBodyShouldContain` "support_award_rates_section"
                response `responseBodyShouldContain` "support_public_holidays_section"

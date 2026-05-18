module Test.Controller.SupportSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import Application.Helper.LiveSurface (typedLiveSurfaceFragmentRefs,
                                       unSurfaceFragmentRefs)
import Application.Helper.LiveUpdate (currentLiveUpdateVersion)
import Application.Helper.LiveUpdate.Internal (LiveUpdateWireFragment)
import Application.Support.LiveUpdates
import Config
import IHP.FrameworkConfig
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Test.Hspec
import Test.Support
import Test.Support.LiveSurfaceContract
import Web.Controller.Support ()
import Web.FrontController ()
import Web.Types

supportFragmentRef :: SupportLiveFragment -> LiveUpdateWireFragment
supportFragmentRef fragment =
    case unSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs supportLiveSurfaceDefinition () [fragment]) of
        [fragmentRef] -> fragmentRef
        _             -> error "Expected one support fragment ref"

tests :: Spec
tests = beforeAll testContext do
    describe "SupportController" do
        it "redirects unauthenticated users from live support fragments" $ withContext do
            response <- callAction ShowFwcMapdAwardRatesSectionAction

            liveFragmentResponseShouldBeDenied status302 response

        it "redirects ordinary users from live support fragments" $ withContext do
            withCleanDb do
                user <- createUserRecord "support-fragment-user@example.com" "staff" True

                response <- withPasskeyVerifiedUser user do
                    callAction ShowPublicHolidaysSectionAction

                liveFragmentResponseShouldBeDenied status302 response

        it "serves live support fragments to super admins through the surface rule" $ withContext do
            withCleanDb do
                superAdmin <- createUserRecordWithPlatformRole "support-fragment-super@example.com" "staff" (Just SuperAdminRole) True

                awardRatesResponse <- withPasskeyVerifiedUser superAdmin do
                    callAction ShowFwcMapdAwardRatesSectionAction
                publicHolidaysResponse <- withPasskeyVerifiedUser superAdmin do
                    callAction ShowPublicHolidaysSectionAction

                liveFragmentResponseShouldRenderTarget awardRatesResponse (supportFragmentRef SupportAwardRatesLiveFragment)
                liveFragmentResponseShouldRenderTarget publicHolidaysResponse (supportFragmentRef SupportPublicHolidaysLiveFragment)

        it "mounts support live surface metadata for super admins" $ withContext do
            withCleanDb do
                superAdmin <- createUserRecordWithPlatformRole "support-surface-super@example.com" "staff" (Just SuperAdminRole) True

                response <- withPasskeyVerifiedUser superAdmin do
                    callAction SupportAction

                responseShouldMountLiveSurface response supportLiveSurface

        it "routes support refresh mutations through touched resources" $ withContext do
            withCleanDb do
                superAdmin <- createUserRecordWithPlatformRole "support-mutation-super@example.com" "staff" (Just SuperAdminRole) True
                versionBefore <- currentLiveUpdateVersion supportLiveUpdateScope

                response <- withPasskeyVerifiedUser superAdmin do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction CreatePublicHolidayRefreshJobAction
                versionAfter <- currentLiveUpdateVersion supportLiveUpdateScope

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"support-public-holidays-section\""
                versionAfter `shouldBe` versionBefore + 1

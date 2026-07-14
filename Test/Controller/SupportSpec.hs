module Test.Controller.SupportSpec where

import Application.Async.Queue (activeAppJobStatuses)
import Application.FwcMapd.Job (fwcMapdRefreshJobKind)
import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountedFragment (..))
import Application.Helper.LiveUpdate
import Application.Support.LiveUpdates
import Config
import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar)
import Control.Exception (SomeException, try)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Test.Hspec
import Test.Support
import Test.Support.SurfaceContract
import Web.Controller.Support ()
import Web.FrontController ()
import Web.Types

supportFragmentRef :: SupportLiveFragment -> FrontendSurfaceMountedFragment
supportFragmentRef fragment =
    case filter ((== supportLiveFragmentKey fragment) . (.mountedFragmentKey)) supportCandidateMountedFragments of
        [fragmentRef] -> fragmentRef
        _             -> error "Expected one support mounted fragment"

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

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-surface=\"support\""
                response `responseBodyShouldContain` "id=\"support-award-rates\""
                response `responseBodyShouldContain` "hx-target=\"#support-award-rates\""
                response `responseBodyShouldContain` "id=\"support-public-holidays\""
                response `responseBodyShouldContain` "hx-target=\"#support-public-holidays\""

        it "shows submitted feedback without the submit-feedback button for super admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Support Venue"
                submitter <- createUserRecord "feedback-support-user@example.com" "staff" True
                superAdmin <- createUserRecordWithPlatformRole "feedback-support-super@example.com" "staff" (Just SuperAdminRole) True
                _ <- newRecord @UserFeedbackItem
                    |> set #venueId (unpackId venue.id)
                    |> set #submittedByUserId (unpackId submitter.id)
                    |> set #feedbackType "bug"
                    |> set #status "new"
                    |> set #priority "normal"
                    |> set #content "Roster page needs a clearer publish button"
                    |> createRecord

                response <- withPasskeyVerifiedUser superAdmin do
                    callAction SupportAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "User Feedback"
                response `responseBodyShouldContain` "Roster page needs a clearer publish button"
                response `responseBodyShouldContain` "feedback-support-user@example.com"
                response `responseBodyShouldContain` "Unread feedback: <span class=\"fw-semibold\">1</span>"
                response `responseBodyShouldNotContain` "hx-get=\"/NewFeedback\""

        it "marks feedback read for super admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Read Venue"
                submitter <- createUserRecord "feedback-read-user@example.com" "staff" True
                superAdmin <- createUserRecordWithPlatformRole "feedback-read-super@example.com" "staff" (Just SuperAdminRole) True
                feedbackItem <- newRecord @UserFeedbackItem
                    |> set #venueId (unpackId venue.id)
                    |> set #submittedByUserId (unpackId submitter.id)
                    |> set #feedbackType "suggestion"
                    |> set #status "new"
                    |> set #priority "normal"
                    |> set #content "Make the copy week action clearer"
                    |> createRecord

                response <- withPasskeyVerifiedUser superAdmin do
                    callAction (MarkFeedbackReadAction feedbackItem.id)

                response `responseStatusShouldBe` status302
                updatedFeedback <- fetch feedbackItem.id
                updatedFeedback.readAt `shouldSatisfy` isJust
                updatedFeedback.readByUserId `shouldBe` Just (unpackId superAdmin.id)

        it "routes support refresh mutations through touched resources" $ withContext do
            withCleanDb do
                superAdmin <- createUserRecordWithPlatformRole "support-mutation-super@example.com" "staff" (Just SuperAdminRole) True
                versionBefore <- currentLiveUpdateVersion supportSurfaceScope

                response <- withPasskeyVerifiedUser superAdmin do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction CreatePublicHolidayRefreshJobAction
                versionAfter <- currentLiveUpdateVersion supportSurfaceScope

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"support-public-holidays\""
                versionAfter `shouldBe` versionBefore

        it "deduplicates concurrent award-rate refresh enqueues without 500s" $ withContext do
            withCleanDb do
                superAdmin <- createUserRecordWithPlatformRole "support-concurrent-super@example.com" "staff" (Just SuperAdminRole) True
                ensureTestUserHasPasskey superAdmin

                results <- runConcurrentActions 12 do
                    withPasskeyVerifiedUser superAdmin do
                        withRequestHeaders [("HX-Request", "true")] do
                            callAction CreateFwcMapdRefreshJobAction

                let failures = lefts results
                failures `shouldSatisfy` null
                let responses = rights results
                length responses `shouldBe` 12
                mapM_ (`responseStatusShouldBe` status200) responses

                activeJobs <- query @AppJob
                    |> filterWhere (#jobKind, fwcMapdRefreshJobKind)
                    |> filterWhereIn (#status, activeAppJobStatuses)
                    |> fetch
                length activeJobs `shouldBe` 1

runConcurrentActions :: Int -> IO a -> IO [Either SomeException a]
runConcurrentActions count action = do
    vars <- mapM (const newEmptyMVar) [1 .. count]
    _ <- mapM (\var -> forkIO (try action >>= putMVar var)) vars
    mapM takeMVar vars

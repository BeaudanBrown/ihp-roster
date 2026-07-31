module Test.Controller.SupportSpec where

import Application.Async.Queue (activeAppJobStatuses)
import Application.FwcMapd.Job (fwcMapdRefreshJobKind)
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
tests = aroundAll withDatabaseTestContext do
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
                superAdmin <- createUserRecordWithPlatformRole "support-fragment-super@example.com" "staff" (Just SuperAdmin) True

                awardRatesResponse <- withPasskeyVerifiedUser superAdmin do
                    callAction ShowFwcMapdAwardRatesSectionAction
                publicHolidaysResponse <- withPasskeyVerifiedUser superAdmin do
                    callAction ShowPublicHolidaysSectionAction

                liveFragmentResponseShouldRenderTarget awardRatesResponse (supportFragmentRef SupportAwardRatesLiveFragment)
                liveFragmentResponseShouldRenderTarget publicHolidaysResponse (supportFragmentRef SupportPublicHolidaysLiveFragment)

        it "mounts support live surface metadata for super admins" $ withContext do
            withCleanDb do
                superAdmin <- createUserRecordWithPlatformRole "support-surface-super@example.com" "staff" (Just SuperAdmin) True

                response <- withPasskeyVerifiedUser superAdmin do
                    callAction SupportAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-surface=\"support\""
                response `responseBodyShouldContain` "id=\"support-award-rates\""
                response `responseBodyShouldContain` "hx-target=\"#support-award-rates\""
                response `responseBodyShouldContain` "id=\"support-public-holidays\""
                response `responseBodyShouldContain` "hx-target=\"#support-public-holidays\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"create-public-holiday-refresh-job\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"create-fwc-mapd-refresh-job\""

        it "shows submitted feedback without the submit-feedback button for super admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Support Venue"
                submitter <- createUserRecord "feedback-support-user@example.com" "staff" True
                superAdmin <- createUserRecordWithPlatformRole "feedback-support-super@example.com" "staff" (Just SuperAdmin) True
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
                response `responseBodyShouldContain` ">Info</summary>"
                response `responseBodyShouldContain` "Page</dt>"
                response `responseBodyShouldContain` "Not reported"
                response `responseBodyShouldNotContain` "hx-get=\"/NewFeedback\""

        it "shows captured feedback diagnostics inline" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Diagnostics Venue"
                submitter <- createUserRecord "feedback-diagnostics-user@example.com" "staff" True
                superAdmin <- createUserRecordWithPlatformRole "feedback-diagnostics-super@example.com" "staff" (Just SuperAdminRole) True
                _ <- newRecord @UserFeedbackItem
                    |> set #venueId (unpackId venue.id)
                    |> set #submittedByUserId (unpackId submitter.id)
                    |> set #feedbackType "bug"
                    |> set #status "new"
                    |> set #priority "normal"
                    |> set #content "Diagnostics are available"
                    |> set #submittedPath (Just "/LeaveRequests")
                    |> set #userAgent (Just "FeedbackBrowser/1.0")
                    |> set #submittedRole (Just "venue_admin")
                    |> set #viewportWidth (Just 390)
                    |> set #viewportHeight (Just 844)
                    |> set #devicePixelRatio (Just 2.625)
                    |> set #deviceClass (Just "mobile")
                    |> set #displayMode (Just "standalone")
                    |> createRecord

                response <- withPasskeyVerifiedUser superAdmin do
                    callAction SupportAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Feedback Diagnostics Venue"
                response `responseBodyShouldContain` "/LeaveRequests"
                response `responseBodyShouldContain` "FeedbackBrowser/1.0"
                response `responseBodyShouldContain` "Venue admin"
                response `responseBodyShouldContain` "390 × 844"
                response `responseBodyShouldContain` "2.625"
                response `responseBodyShouldContain` "Mobile"
                response `responseBodyShouldContain` "Standalone PWA"

        it "marks feedback read for super admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Read Venue"
                submitter <- createUserRecord "feedback-read-user@example.com" "staff" True
                superAdmin <- createUserRecordWithPlatformRole "feedback-read-super@example.com" "staff" (Just SuperAdmin) True
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
                superAdmin <- createUserRecordWithPlatformRole "support-mutation-super@example.com" "staff" (Just SuperAdmin) True
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
                superAdmin <- createUserRecordWithPlatformRole "support-concurrent-super@example.com" "staff" (Just SuperAdmin) True
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

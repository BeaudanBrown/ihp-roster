module Test.Controller.HelpSpec where

import Application.Helper.FrontendContract.Overlay.Runtime (OverlayDom (..),
                                                            canonicalOverlayDom)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.Prelude
import IHP.Hspec
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Test.Hspec
import Test.Support
import Web.Controller.Help ()
import Web.FrontController ()
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "HelpController" do
        it "renders HTMX page help dialog through the shared overlay" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Help Dialog Venue"
                user <- createUserRecord "help-dialog@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker

                response <- withPasskeyVerifiedUserAndCurrentVenue user (get #id venue) do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction ShowPageHelpAction { topic = "roster" }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` (cs canonicalOverlayDom.overlayDialogMountAttribute)
                response `responseBodyShouldContain` "Roster"
                response `responseBodyShouldContain` "Staff"
                response `responseBodyShouldContain` "future roster"
                response `responseBodyShouldNotContain` "Hold Ctrl"

        it "shows manager-only roster details to managers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Help Manager Venue"
                user <- createUserRecord "help-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Manager

                response <- withPasskeyVerifiedUserAndCurrentVenue user (get #id venue) do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction ShowPageHelpAction { topic = "roster" }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Hold Ctrl"
                response `responseBodyShouldContain` "Option, or Alt"

        it "explains effective support identity and hides unavailable security guidance while impersonating" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonated Help Venue"
                founder <- createUserRecordWithPlatformRole "help-impersonated-founder@example.com" "staff" (Just SuperAdmin) True
                worker <- createUserRecord "help-impersonated-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                _ <- createStaffRecord venue (Just worker) "Help" "Worker"

                (founderResponse, response) <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    founderResponse <- withRequestHeaders [("HX-Request", "true")] do
                        callAction ShowPageHelpAction { topic = "profile" }
                    _ <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue worker.id))]
                    response <- withRequestHeaders [("HX-Request", "true")] do
                        callAction ShowPageHelpAction { topic = "profile" }
                    pure (founderResponse, response)

                founderResponse `responseStatusShouldBe` status200
                founderResponse `responseBodyShouldContain` "Founder support"
                founderResponse `responseBodyShouldContain` "Viewing as a venue user"
                founderResponse `responseBodyShouldContain` "Manage account security"
                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Founder support"
                response `responseBodyShouldContain` "Viewing as a venue user"
                response `responseBodyShouldContain` "Selecting a venue user in View as applies access from that user"
                response `responseBodyShouldContain` "Choose Super admin from View as to exit immediately"
                response `responseBodyShouldContain` "Account security changes are blocked while viewing as a venue user"
                response `responseBodyShouldNotContain` "Manage account security"
                response `responseBodyShouldNotContain` "Use passkey and recovery options"

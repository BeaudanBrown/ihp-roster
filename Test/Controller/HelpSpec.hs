module Test.Controller.HelpSpec where

import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Test.Hspec
import Test.Support
import Web.Controller.Help ()
import Web.FrontController ()
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "HelpController" do
        it "renders HTMX page help dialog through the shared overlay" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Help Dialog Venue"
                user <- createUserRecord "help-dialog@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"

                response <- withPasskeyVerifiedUserAndCurrentVenue user (get #id venue) do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction ShowPageHelpAction { topic = "roster" }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-dialog-overlay=\"true\""
                response `responseBodyShouldContain` "Roster"
                response `responseBodyShouldContain` "Staff"
                response `responseBodyShouldContain` "future roster"
                response `responseBodyShouldNotContain` "Hold Ctrl"

        it "shows manager-only roster details to managers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Help Manager Venue"
                user <- createUserRecord "help-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "manager"

                response <- withPasskeyVerifiedUserAndCurrentVenue user (get #id venue) do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction ShowPageHelpAction { topic = "roster" }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Hold Ctrl"
                response `responseBodyShouldContain` "Option, or Alt"

module Test.Controller.FeedbackSpec where

import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Test.Hspec
import Test.Support
import Web.Controller.Feedback ()
import Web.FrontController ()
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "FeedbackController" do
        it "renders HTMX feedback dialog forms through generated AppShellAction metadata" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Dialog Venue"
                user <- createUserRecord "feedback-dialog@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"

                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction NewFeedbackAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "data-bepis-app-shell-action="
                response `responseBodyShouldContain` "hx-post=\"/CreateFeedback\""
                response `responseBodyShouldContain` "hx-target=\"#dialog-overlay-mount\""

        it "creates venue-scoped feedback for signed-in users" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Venue"
                user <- createUserRecord "feedback-user@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"

                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true"), ("User-Agent", "FeedbackSpec/1.0")] do
                        callActionWithParams CreateFeedbackAction
                            [ ("feedbackType", "suggestion")
                            , ("content", "  Please add a daily print view.  ")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Thanks"
                feedbackItems <- query @UserFeedbackItem |> fetch
                length feedbackItems `shouldBe` 1
                let [feedbackItem] = feedbackItems
                feedbackItem.venueId `shouldBe` unpackId venue.id
                feedbackItem.submittedByUserId `shouldBe` unpackId user.id
                feedbackItem.feedbackType `shouldBe` "suggestion"
                feedbackItem.content `shouldBe` "Please add a daily print view."
                feedbackItem.userAgent `shouldBe` Just "FeedbackSpec/1.0"

        it "rejects missing feedback content without creating a row" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Required Venue"
                user <- createUserRecord "feedback-required@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"

                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateFeedbackAction
                            [ ("feedbackType", "bug")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Please enter at least 3 characters"
                feedbackExists <- query @UserFeedbackItem |> fetchExists
                feedbackExists `shouldBe` False

        it "rejects invalid feedback types" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Type Venue"
                user <- createUserRecord "feedback-type@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"

                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateFeedbackAction
                            [ ("feedbackType", "billing_secret")
                            , ("content", "This should not save")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Choose a feedback type"
                feedbackExists <- query @UserFeedbackItem |> fetchExists
                feedbackExists `shouldBe` False

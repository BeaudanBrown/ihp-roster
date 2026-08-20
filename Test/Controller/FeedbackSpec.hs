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
                _ <- createVenueMembershipRecord venue user Worker

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
                _ <- createVenueMembershipRecord venue user Worker

                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id do
                    withRequestHeaders
                        [ ("HX-Request", "true")
                        , ("User-Agent", "FeedbackSpec/1.0")
                        , ("Host", "app.example")
                        , ("Referer", "https://app.example/LeaveRequests?staff=secret#private")
                        ] do
                        callActionWithParams CreateFeedbackAction
                            [ ("feedbackType", "suggestion")
                            , ("content", "  Please add a daily print view.  ")
                            , ("feedbackOriginPath", "/invented-path?forged=secret")
                            , ("feedbackViewportWidth", "390")
                            , ("feedbackViewportHeight", "844")
                            , ("feedbackDevicePixelRatio", "2.625")
                            , ("feedbackDisplayMode", "standalone")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Thanks"
                feedbackItems <- query @UserFeedbackItem |> fetch
                length feedbackItems `shouldBe` 1
                let [feedbackItem] = feedbackItems
                feedbackItem.venueId `shouldBe` unpackId venue.id
                feedbackItem.submittedByUserId `shouldBe` unpackId user.id
                feedbackItem.feedbackType `shouldBe` Suggestion
                feedbackItem.content `shouldBe` "Please add a daily print view."
                feedbackItem.userAgent `shouldBe` Just "FeedbackSpec/1.0"
                feedbackItem.submittedPath `shouldBe` Just "/LeaveRequests"
                feedbackItem.submittedRole `shouldBe` Just "worker"
                feedbackItem.viewportWidth `shouldBe` Just 390
                feedbackItem.viewportHeight `shouldBe` Just 844
                feedbackItem.devicePixelRatio `shouldBe` Just 2.625
                feedbackItem.deviceClass `shouldBe` Just "mobile"
                feedbackItem.displayMode `shouldBe` Just "standalone"

        it "creates feedback when browser diagnostics are missing or malformed" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Best Effort Venue"
                user <- createUserRecord "feedback-best-effort@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Manager

                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id do
                    withRequestHeaders
                        [ ("HX-Request", "true")
                        , ("Host", "app.example")
                        , ("Referer", "https://app.example/CreateFeedback?token=bad")
                        ] do
                        callActionWithParams CreateFeedbackAction
                            [ ("feedbackType", "bug")
                            , ("content", "Browser metadata must remain optional")
                            , ("feedbackOriginPath", "/invented-path")
                            , ("feedbackViewportWidth", "-1")
                            , ("feedbackViewportHeight", "not-a-number")
                            , ("feedbackDevicePixelRatio", "NaN")
                            , ("feedbackDisplayMode", "installed-with-secrets")
                            ]

                response `responseStatusShouldBe` status200
                feedbackItem <- query @UserFeedbackItem |> fetchOne
                feedbackItem.submittedPath `shouldBe` Nothing
                feedbackItem.submittedRole `shouldBe` Just "manager"
                feedbackItem.userAgent `shouldBe` Nothing
                feedbackItem.viewportWidth `shouldBe` Nothing
                feedbackItem.viewportHeight `shouldBe` Nothing
                feedbackItem.devicePixelRatio `shouldBe` Nothing
                feedbackItem.deviceClass `shouldBe` Nothing
                feedbackItem.displayMode `shouldBe` Nothing

        it "persists the direct feedback page as the no-JavaScript origin" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback No JavaScript Venue"
                user <- createUserRecord "feedback-no-js@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker

                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id do
                    withRequestHeaders
                        [ ("Host", "app.example")
                        , ("Referer", "https://app.example/NewFeedback?ignored=secret")
                        ] do
                        callActionWithParams CreateFeedbackAction
                            [ ("feedbackType", "bug")
                            , ("content", "The native feedback form still submits")
                            ]

                response `responseStatusShouldBe` status302
                feedbackItem <- query @UserFeedbackItem |> fetchOne
                feedbackItem.submittedPath `shouldBe` Just "/NewFeedback"
                feedbackItem.viewportWidth `shouldBe` Nothing

        it "snapshots platform support submissions distinctly from venue roles" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Support Role Venue"
                supportUser <- createUserRecordWithPlatformRole "feedback-role-support@example.com" "staff" (Just SuperAdmin) True

                response <- withPasskeyVerifiedUserAndCurrentVenue supportUser venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateFeedbackAction
                            [ ("feedbackType", "bug")
                            , ("content", "Support context needs a distinct role")
                            ]

                response `responseStatusShouldBe` status200
                feedbackItem <- query @UserFeedbackItem |> fetchOne
                feedbackItem.submittedRole `shouldBe` Just "support_super_admin"

        it "rejects missing feedback content without creating a row" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Required Venue"
                user <- createUserRecord "feedback-required@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker

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
                _ <- createVenueMembershipRecord venue user Worker

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

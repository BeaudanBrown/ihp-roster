module Test.Controller.FeedbackSpec where

import Application.EmailDelivery (emailDeliveryJobKind)
import Application.Feedback.Domain (publishFeedback, archiveFeedback, addFeedbackVote)
import Application.Feedback.ReadModel (PublicFeedbackCard (..), fetchPublicFeedbackCards)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Text as Text
import Data.Time (UTCTime (..), fromGregorian)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders)
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
                firstSupport <- createUserRecordWithPlatformRole "first-support@example.com" "staff" (Just SuperAdmin) True
                secondSupport <- createUserRecordWithPlatformRole "second-support@example.com" "staff" (Just SuperAdmin) True
                inactiveSupport <- createUserRecordWithPlatformRole "inactive-support@example.com" "staff" (Just SuperAdmin) True
                now <- getCurrentTime
                _ <- inactiveSupport |> set #deactivatedAt (Just now) |> updateRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id do
                    withRequestHeaders
                        [ ("HX-Request", "true")
                        , ("User-Agent", "FeedbackSpec/1.0")
                        , ("Host", "app.example")
                        , ("Referer", "https://app.example/LeaveRequests?staff=secret#private")
                        ] do
                        callActionWithParams CreateFeedbackAction
                            [ ("feedbackType", "suggestion")
                            , ("feedbackTitle", "  Daily print view  ")
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
                feedbackItem.title `shouldBe` "Daily print view"
                feedbackItem.lifecycle `shouldBe` Private
                feedbackItem.userAgent `shouldBe` Nothing
                feedbackItem.submittedPath `shouldBe` Nothing
                feedbackItem.submittedRole `shouldBe` Nothing
                feedbackItem.viewportWidth `shouldBe` Nothing
                feedbackItem.viewportHeight `shouldBe` Nothing
                feedbackItem.devicePixelRatio `shouldBe` Nothing
                feedbackItem.deviceClass `shouldBe` Nothing
                feedbackItem.displayMode `shouldBe` Nothing
                response `responseBodyShouldContain` "submitted for review"

                jobs <- query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> orderByAsc #createdAt |> fetch
                length jobs `shouldBe` 2
                map payloadRecipientAccountId jobs `shouldMatchList` map (Just . unpackId . (.id)) [firstSupport, secondSupport]
                map payloadRecipientAddress jobs `shouldMatchList` [Just "first-support@example.com", Just "second-support@example.com"]
                map (.relatedId) jobs `shouldBe` replicate 2 (Just (unpackId feedbackItem.id))
                map (.requestedByUserId) jobs `shouldBe` replicate 2 (Just (unpackId user.id))
                forM_ jobs \job -> do
                    job.payloadSchemaVersion `shouldBe` 1
                    tshow job.payload `shouldSatisfy` (not . Text.isInfixOf feedbackItem.content)
                    fromMaybe "" job.dedupeKey `shouldSatisfy` (not . Text.isInfixOf "@example.com")

        it "creates feedback with no delivery jobs when no active super admin exists" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback No Recipient Venue"
                user <- createUserRecord "feedback-no-recipient@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker

                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateFeedbackAction
                            [ ("feedbackType", "bug")
                            , ("feedbackTitle", "No recipient")
                            , ("content", "Saving must not require a support recipient")
                            ]

                response `responseStatusShouldBe` status200
                query @UserFeedbackItem |> fetchCount >>= (`shouldBe` 1)
                query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetchCount >>= (`shouldBe` 0)

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
                            , ("feedbackTitle", "No diagnostics")
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
                feedbackItem.submittedRole `shouldBe` Nothing
                feedbackItem.userAgent `shouldBe` Nothing
                feedbackItem.viewportWidth `shouldBe` Nothing
                feedbackItem.viewportHeight `shouldBe` Nothing
                feedbackItem.devicePixelRatio `shouldBe` Nothing
                feedbackItem.deviceClass `shouldBe` Nothing
                feedbackItem.displayMode `shouldBe` Nothing

        it "accepts native submission without capturing the no-JavaScript origin" $ withContext do
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
                            , ("feedbackTitle", "Native form")
                            , ("content", "The native feedback form still submits")
                            ]

                response `responseStatusShouldBe` status302
                feedbackItem <- query @UserFeedbackItem |> fetchOne
                feedbackItem.submittedPath `shouldBe` Nothing
                feedbackItem.lifecycle `shouldBe` Private
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/Feedback"
                feedbackItem.viewportWidth `shouldBe` Nothing

        it "accepts platform support submissions without retaining a role diagnostic" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Support Role Venue"
                supportUser <- createUserRecordWithPlatformRole "feedback-role-support@example.com" "staff" (Just SuperAdmin) True

                response <- withPasskeyVerifiedUserAndCurrentVenue supportUser venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateFeedbackAction
                            [ ("feedbackType", "bug")
                            , ("feedbackTitle", "Support submission")
                            , ("content", "Support context needs a distinct role")
                            ]

                response `responseStatusShouldBe` status200
                feedbackItem <- query @UserFeedbackItem |> fetchOne
                feedbackItem.submittedRole `shouldBe` Nothing

        it "rejects missing feedback content without creating a row" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Required Venue"
                user <- createUserRecord "feedback-required@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker

                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateFeedbackAction
                            [ ("feedbackType", "bug")
                            , ("feedbackTitle", "Missing content")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Please enter at least 3 characters"
                feedbackExists <- query @UserFeedbackItem |> fetchExists
                feedbackExists `shouldBe` False
                query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetchCount >>= (`shouldBe` 0)

        it "rejects invalid feedback types" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Type Venue"
                user <- createUserRecord "feedback-type@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker

                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateFeedbackAction
                            [ ("feedbackType", "billing_secret")
                            , ("feedbackTitle", "Invalid type")
                            , ("content", "This should not save")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Choose a feedback type"
                feedbackExists <- query @UserFeedbackItem |> fetchExists
                feedbackExists `shouldBe` False
                query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetchCount >>= (`shouldBe` 0)

        forM_ [Worker, Supervisor, Manager, VenueAdmin, VenueOwner] \role ->
            it ("shows only global public cards to " <> cs (tshow role)) $ withContext do
                withCleanDb do
                    venue <- createVenueWithConfig "Reader venue"
                    origin <- createVenueWithConfig "Secret origin venue"
                    user <- createUserRecord "reader@example.com" "staff" True
                    author <- createUserRecord "secret-author@example.com" "staff" True
                    moderator <- createUserRecordWithPlatformRole "moderator@example.com" "staff" (Just SuperAdmin) True
                    _ <- createVenueMembershipRecord venue user role
                    privateItem <- feedbackFixture origin author "Secret private title"
                    archivedItem <- feedbackFixture origin author "Secret archived title"
                    Right _ <- archiveFeedback archivedItem.id moderator.id (UTCTime (fromGregorian 2026 9 1) 43200)
                    publicItem <- feedbackFixture origin author "Shared public title"
                    Right _ <- publishFeedback publicItem.id moderator.id (UTCTime (fromGregorian 2026 9 1) 43200)

                    response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id do
                        callAction FeedbackAction
                    response `responseStatusShouldBe` status200
                    response `responseBodyShouldContain` "Shared public title"
                    response `responseBodyShouldContain` "1 votes"
                    response `responseBodyShouldContain` "Add feedback"
                    forM_ ["Secret private title", "Secret archived title", "secret-author@example.com", "Secret origin venue", "Secret support note", "/secret-path", tshow privateItem.id, tshow archivedItem.id] \secret ->
                        response `responseBodyShouldNotContain` secret

        it "shows the empty board and navigation to platform support without membership" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Support board venue"
                moderator <- createUserRecordWithPlatformRole "board-support@example.com" "staff" (Just SuperAdmin) True
                response <- withPasskeyVerifiedUserAndCurrentVenue moderator venue.id do
                    callAction FeedbackAction
                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "No public feedback yet"
                response `responseBodyShouldContain` "href=\"/Feedback\""
                response `responseBodyShouldContain` "href=\"/NewFeedback\""

        it "does not reveal a new submission to its author on the public board" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Author venue"
                author <- createUserRecord "private-author@example.com" "staff" True
                _ <- createVenueMembershipRecord venue author Worker
                _ <- feedbackFixture venue author "My hidden submission"
                response <- withPasskeyVerifiedUserAndCurrentVenue author venue.id do
                    callAction FeedbackAction
                response `responseBodyShouldNotContain` "My hidden submission"
                response `responseBodyShouldContain` "No public feedback yet"

        it "orders global cards by votes then publication time" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Ordering venue"
                author <- createUserRecord "ordering-author@example.com" "staff" True
                voter <- createUserRecord "ordering-voter@example.com" "staff" True
                moderator <- createUserRecordWithPlatformRole "ordering-support@example.com" "staff" (Just SuperAdmin) True
                older <- feedbackFixture venue author "Older popular idea"
                newer <- feedbackFixture venue author "Newer idea"
                newest <- feedbackFixture venue author "Newest idea"
                Right _ <- publishFeedback older.id moderator.id (UTCTime (fromGregorian 2026 9 1) 0)
                Right _ <- publishFeedback newer.id moderator.id (UTCTime (fromGregorian 2026 9 2) 0)
                Right _ <- publishFeedback newest.id moderator.id (UTCTime (fromGregorian 2026 9 3) 0)
                Right _ <- addFeedbackVote older.id voter.id
                cards <- fetchPublicFeedbackCards
                map (.title) cards `shouldBe` ["Older popular idea", "Newest idea", "Newer idea"]
                map (.voteCount) cards `shouldBe` [2, 1, 1]

        it "uses ordinary privacy and effective submitter identity during support impersonation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonation board venue"
                founder <- createUserRecordWithPlatformRole "board-founder@example.com" "staff" (Just SuperAdmin) True
                worker <- createUserRecord "board-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                _ <- feedbackFixture venue founder "Hidden founder feedback"
                withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    _ <- callActionWithParams StartSupportImpersonationAction [("userId", cs (inputValue worker.id))]
                    response <- callAction FeedbackAction
                    response `responseStatusShouldBe` status200
                    response `responseBodyShouldNotContain` "Hidden founder feedback"
                    _ <- callActionWithParams CreateFeedbackAction
                        [("feedbackType", "suggestion"), ("feedbackTitle", "Effective submission"), ("content", "From the effective worker")]
                    submitted <- query @UserFeedbackItem |> filterWhere (#title, "Effective submission") |> fetchOne
                    submitted.submittedByUserId `shouldBe` unpackId worker.id
                    submitted.lifecycle `shouldBe` Private

        it "rejects unauthenticated board and dialog routes" $ withContext do
            forM_ [FeedbackAction, NewFeedbackAction] \action -> do
                response <- callAction action
                response `responseStatusShouldBe` status302

        forM_ [Nothing, Just "", Just "   ", Just (Text.replicate 121 "x")] \title ->
            it ("rejects missing, blank or oversized title: " <> cs (tshow (fmap Text.length title))) $ withContext do
                withCleanDb do
                    venue <- createVenueWithConfig "Title validation venue"
                    author <- createUserRecord "title-validation@example.com" "staff" True
                    _ <- createVenueMembershipRecord venue author Worker
                    response <- withPasskeyVerifiedUserAndCurrentVenue author venue.id do
                        callActionWithParams CreateFeedbackAction
                            ([("feedbackType", "bug"), ("content", "Valid description")] <> maybe [] (\value -> [("feedbackTitle", cs value)]) title)
                    response `responseStatusShouldBe` status200
                    query @UserFeedbackItem |> fetchCount >>= (`shouldBe` 0)

feedbackFixture :: (?modelContext :: ModelContext) => Venue -> User -> Text -> IO UserFeedbackItem
feedbackFixture venue author title = newRecord @UserFeedbackItem
    |> set #venueId (unpackId venue.id)
    |> set #submittedByUserId (unpackId author.id)
    |> set #title title
    |> set #content "A shared improvement description"
    |> set #supportNote (Just "Secret support note")
    |> set #submittedPath (Just "/secret-path")
    |> createRecord

payloadRecipientAccountId :: AppJob -> Maybe UUID
payloadRecipientAccountId appJob =
    AesonTypes.parseMaybe (Aeson.withObject "email delivery payload" (Aeson..: "recipientAccountId")) appJob.payload

payloadRecipientAddress :: AppJob -> Maybe Text
payloadRecipientAddress appJob =
    AesonTypes.parseMaybe (Aeson.withObject "email delivery payload" (Aeson..: "recipientAddress")) appJob.payload

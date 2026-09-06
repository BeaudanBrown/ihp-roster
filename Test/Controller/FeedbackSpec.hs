module Test.Controller.FeedbackSpec where

import Application.EmailDelivery (emailDeliveryJobKind)
import Application.Feedback.Domain (publishFeedback, archiveFeedback, addFeedbackVote)
import Application.Feedback.ReadModel (PublicFeedbackCard (..), fetchPublicFeedbackCards)
import Application.Helper.FrontendContract.Surface.Feedback.Live (feedbackPlatformLiveScope)
import Web.SurfaceInvalidation (authorizeSurfaceScope)
import qualified Control.Exception as Exception
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

        it "shows empty management sections and navigation to platform support without membership" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Support board venue"
                moderator <- createUserRecordWithPlatformRole "board-support@example.com" "staff" (Just SuperAdmin) True
                response <- withPasskeyVerifiedUserAndCurrentVenue moderator venue.id do
                    callAction FeedbackAction
                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Private (0)"
                response `responseBodyShouldContain` "Public (0)"
                response `responseBodyShouldContain` "Archived (0)"
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

        it "renders all management rows and retained metadata only to the unimpersonated founder" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Management origin"
                otherVenue <- createVenueWithConfig "Unrelated support venue"
                author <- createUserRecord "management-author@example.com" "staff" True
                founder <- createUserRecordWithPlatformRole "management-founder@example.com" "staff" (Just SuperAdmin) True
                forM_ [1..51 :: Int] \index -> feedbackFixture venue author ("Private card " <> tshow index)
                withPasskeyVerifiedUserAndCurrentVenue founder otherVenue.id do
                    response <- callAction FeedbackAction
                    response `responseBodyShouldContain` "Private (51)"
                    response `responseBodyShouldContain` "Private card 1"
                    response `responseBodyShouldContain` "Private card 51"
                    response `responseBodyShouldContain` "management-author@example.com"
                    response `responseBodyShouldContain` "Secret support note"
                    response `responseBodyShouldContain` "/secret-path"
                    response `responseBodyShouldContain` "Management origin"
                    response `responseBodyShouldContain` "hx-get=\"/EditFeedback"
                    countResponse <- callAction ShowFeedbackDesktopCountAction
                    countResponse `responseBodyShouldContain` ">51</span>"
                    countResponse `responseBodyShouldNotContain` "hx-swap-oob"
                    review <- callAction ShowFeedbackReviewAction
                    review `responseBodyShouldContain` "Private (51)"
                    review `responseBodyShouldNotContain` "<!DOCTYPE"
                    withCurrentControllerContext (authorizeSurfaceScope feedbackPlatformLiveScope) `shouldReturn` True

        forM_ [Worker, Supervisor, Manager, VenueAdmin, VenueOwner] \role ->
            it ("denies moderation endpoints and subscriptions to " <> cs (tshow role)) $ withContext do
                withCleanDb do
                    venue <- createVenueWithConfig "Authority venue"
                    user <- createUserRecord "moderation-denied@example.com" "staff" True
                    _ <- createVenueMembershipRecord venue user role
                    item <- feedbackFixture venue user "Do not publish"
                    withPasskeyVerifiedUserAndCurrentVenue user venue.id do
                        forM_ (moderationRoutes item.id) \route -> do
                            response <- callAction route
                            response `responseStatusShouldBe` status403
                            response `responseBodyShouldNotContain` "Secret support note"
                        withCurrentControllerContext (authorizeSurfaceScope feedbackPlatformLiveScope) `shouldReturn` False
                    saved <- fetch item.id
                    saved.lifecycle `shouldBe` Private
                    query @FeedbackVote |> fetchCount >>= (`shouldBe` 0)
                    query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` 0)

        it "excludes an actual founder impersonating an ordinary effective user from every moderation route" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonation moderation"
                founder <- createUserRecordWithPlatformRole "moderation-actual@example.com" "staff" (Just SuperAdmin) True
                worker <- createUserRecord "moderation-effective@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                item <- feedbackFixture venue worker "Private under impersonation"
                withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    _ <- callActionWithParams StartSupportImpersonationAction [("userId", cs (inputValue worker.id))]
                    forM_ (moderationRoutes item.id) \route -> do
                        response <- callAction route
                        response `responseStatusShouldBe` status403
                        response `responseBodyShouldNotContain` "Secret support note"
                    withCurrentControllerContext (authorizeSurfaceScope feedbackPlatformLiveScope) `shouldReturn` False

        it "commits editorial transitions, votes, audit provenance and actor invalidations together" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Moderated origin"
                otherVenue <- createVenueWithConfig "Current support venue"
                author <- createUserRecord "lifecycle-author@example.com" "staff" True
                founder <- createUserRecordWithPlatformRole "lifecycle-founder@example.com" "staff" (Just SuperAdmin) True
                item <- feedbackFixture venue author "Editorial original"
                withPasskeyVerifiedUserAndCurrentVenue founder otherVenue.id do
                    response <- withRequestHeaders [("HX-Request", "true")] (callAction (PublishFeedbackAction item.id))
                    response `responseStatusShouldBe` status200
                    lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                    lookup "HX-Trigger" (responseHeaders response) `shouldSatisfy` isJust
                    response `responseBodyShouldNotContain` "Editorial original"
                    published <- fetch item.id
                    published.lifecycle `shouldBe` Public
                    published.publishedByUserId `shouldBe` Just (unpackId founder.id)
                    vote <- query @FeedbackVote |> fetchOne
                    vote.userId `shouldBe` unpackId author.id
                    _ <- callActionWithParams (UpdateFeedbackAction item.id)
                        [("feedbackTitle", "  Edited title  "), ("feedbackContent", "Edited description"), ("feedbackType", "suggestion")]
                    edited <- fetch item.id
                    edited.title `shouldBe` "Edited title"
                    edited.feedbackType `shouldBe` Suggestion
                    query @FeedbackVote |> fetchCount >>= (`shouldBe` 1)
                    publicReview <- callAction ShowFeedbackReviewAction
                    publicReview `responseBodyShouldContain` "All votes will be removed."
                    _ <- callAction (ArchiveFeedbackAction item.id)
                    archived <- fetch item.id
                    archived.lifecycle `shouldBe` Archived
                    archived.archivedByUserId `shouldBe` Just (unpackId founder.id)
                    query @FeedbackVote |> fetchCount >>= (`shouldBe` 0)
                    _ <- callAction (RestoreFeedbackAction item.id)
                    restored <- fetch item.id
                    restored.lifecycle `shouldBe` Private
                    restored.publishedAt `shouldBe` Nothing
                    restored.publishedByUserId `shouldBe` Nothing
                    restored.archivedAt `shouldBe` Nothing
                    restored.archivedByUserId `shouldBe` Nothing
                    _ <- callAction (PublishFeedbackAction item.id)
                    query @FeedbackVote |> fetchCount >>= (`shouldBe` 1)
                    events <- query @AuditEvent |> filterWhere (#targetId, unpackId item.id) |> fetch
                    length events `shouldBe` 5
                    map (.venueId) events `shouldBe` replicate 5 (unpackId venue.id)
                    map (.actorUserId) events `shouldBe` replicate 5 (unpackId founder.id)
                    query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` 5)
                    _ <- callAction (PublishFeedbackAction item.id)
                    query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` 5)

        it "rolls back publication, the automatic vote and audit when durable handoff fails" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Publication rollback"
                founder <- createUserRecordWithPlatformRole "rollback-founder@example.com" "staff" (Just SuperAdmin) True
                item <- feedbackFixture venue founder "Must stay private"
                let installFailure = do
                        sqlExecDiscardResult "CREATE FUNCTION reject_feedback_event() RETURNS trigger AS 'BEGIN RAISE EXCEPTION ''forced feedback publication failure''; END' LANGUAGE plpgsql" ()
                        sqlExecDiscardResult "CREATE TRIGGER reject_feedback_event BEFORE INSERT ON live_invalidation_events FOR EACH ROW EXECUTE FUNCTION reject_feedback_event()" ()
                let removeFailure = do
                        sqlExecDiscardResult "DROP TRIGGER IF EXISTS reject_feedback_event ON live_invalidation_events" ()
                        sqlExecDiscardResult "DROP FUNCTION IF EXISTS reject_feedback_event()" ()
                Exception.bracket_ installFailure removeFailure do
                    _ <- Exception.try @Exception.SomeException $ withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                        callAction (PublishFeedbackAction item.id)
                    pure ()
                saved <- fetch item.id
                saved.lifecycle `shouldBe` Private
                saved.publishedAt `shouldBe` Nothing
                query @FeedbackVote |> fetchCount >>= (`shouldBe` 0)
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` 0)
                query @AuditEvent |> filterWhere (#targetId, unpackId item.id) |> fetchCount >>= (`shouldBe` 0)

        forM_ [ [], [("feedbackTitle", ""), ("feedbackContent", "valid"), ("feedbackType", "bug")]
              , [("feedbackTitle", "valid"), ("feedbackContent", "ab"), ("feedbackType", "bug")]
              , [("feedbackTitle", "valid"), ("feedbackContent", "valid"), ("feedbackType", "invalid")]
              , [("feedbackTitle", cs (Text.replicate 121 "x")), ("feedbackContent", "valid"), ("feedbackType", "bug")]
              , [("feedbackTitle", "valid"), ("feedbackContent", cs (Text.replicate 3001 "x")), ("feedbackType", "bug")]
              ] \params ->
            it ("validates editorial input without publishing facts: " <> cs (tshow (map fst params))) $ withContext do
                withCleanDb do
                    venue <- createVenueWithConfig "Editorial validation"
                    founder <- createUserRecordWithPlatformRole "editor-validation@example.com" "staff" (Just SuperAdmin) True
                    item <- feedbackFixture venue founder "Unchanged title"
                    response <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                        withRequestHeaders [("HX-Request", "true")] (callActionWithParams (UpdateFeedbackAction item.id) params)
                    response `responseStatusShouldBe` status200
                    response `responseBodyShouldContain` "feedback-edit-form"
                    response `responseBodyShouldContain` "invalid-feedback"
                    saved <- fetch item.id
                    saved.title `shouldBe` "Unchanged title"
                    query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` 0)
                    query @AuditEvent |> filterWhere (#targetId, unpackId item.id) |> fetchCount >>= (`shouldBe` 0)

moderationRoutes :: Id UserFeedbackItem -> [FeedbackController]
moderationRoutes itemId = [ShowFeedbackReviewAction, ShowFeedbackDesktopCountAction, ShowFeedbackMobileCountAction,
    EditFeedbackAction itemId, UpdateFeedbackAction itemId, PublishFeedbackAction itemId, ArchiveFeedbackAction itemId, RestoreFeedbackAction itemId]

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

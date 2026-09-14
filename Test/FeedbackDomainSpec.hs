module Test.FeedbackDomainSpec where

import Application.Feedback.Domain
import Control.Concurrent.Async (concurrently)
import qualified Control.Exception as Exception
import Data.Either (isLeft, isRight)
import Data.List (sort)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Time.Clock (addUTCTime)
import Generated.Types
import qualified Hasql.Session as HasqlSession
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlExecDiscardResult, sqlQuery, unpackId)
import IHP.ModelSupport.Types (ModelContext (transactionRunner),
                               TransactionRunner (runInTransaction))
import IHP.Test.Mocking (withContext)
import Test.Hspec
import Test.Support

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Feedback domain" do
        it "derives a bounded title from the first non-empty content line" \_ -> do
            deriveFeedbackTitle "  \n First useful line  \nsecond" `shouldBe` "First useful line"
            deriveFeedbackTitle " \n\t" `shouldBe` "Untitled feedback"
            Text.length (deriveFeedbackTitle (Text.replicate 130 "x")) `shouldBe` 120

        it "publishes with the submitter vote, archives atomically, and restores cleanly" $ withContext do
            withCleanDb do
                (feedback, submitter, moderator) <- privateFeedbackFixture
                publishedAt <- getCurrentTime

                Right published <- publishFeedback feedback.id moderator.id publishedAt
                published.lifecycle `shouldBe` Public
                published.publishedByUserId `shouldBe` Just (unpackId moderator.id)
                votesAfterPublish <- query @FeedbackVote |> fetch
                map (.userId) votesAfterPublish `shouldBe` [unpackId submitter.id]
                Right () <- removeFeedbackVote feedback.id submitter.id
                Right _ <- addFeedbackVote feedback.id submitter.id

                Right archived <- archiveFeedback feedback.id moderator.id (addUTCTime 60 publishedAt)
                archived.lifecycle `shouldBe` Archived
                query @FeedbackVote |> fetchCount >>= (`shouldBe` 0)

                Right restored <- restoreFeedback feedback.id
                restored.lifecycle `shouldBe` Private
                restored.publishedAt `shouldBe` Nothing
                restored.archivedAt `shouldBe` Nothing

                Right _ <- publishFeedback feedback.id moderator.id (addUTCTime 120 publishedAt)
                republishedVotes <- query @FeedbackVote |> fetch
                map (.userId) republishedVotes `shouldBe` [unpackId submitter.id]

        it "serializes duplicate concurrent votes by global user account" $ withContext do
            withCleanDb do
                (feedback, _, moderator) <- privateFeedbackFixture
                voter <- createUserRecord "feedback-voter@example.com" "staff" True
                now <- getCurrentTime
                Right _ <- publishFeedback feedback.id moderator.id now

                (left, right) <- concurrently
                    (addFeedbackVote feedback.id voter.id)
                    (addFeedbackVote feedback.id voter.id)

                sort (map voteOutcome [left, right]) `shouldBe` ["created", "duplicate"]
                query @FeedbackVote
                    |> filterWhere (#feedbackItemId, unpackId feedback.id)
                    |> filterWhere (#userId, unpackId voter.id)
                    |> fetchCount
                    >>= (`shouldBe` 1)

        it "serializes concurrent removal and opposing account vote commands" $ withContext do
            withCleanDb do
                (feedback, author, moderator) <- privateFeedbackFixture
                now <- getCurrentTime
                Right _ <- publishFeedback feedback.id moderator.id now
                (first, second) <- concurrently
                    (removeFeedbackVote feedback.id author.id)
                    (removeFeedbackVote feedback.id author.id)
                length (filter (== Right ()) [first, second]) `shouldBe` 1
                length (filter (== Left FeedbackVoteNotFound) [first, second]) `shouldBe` 1
                query @FeedbackVote |> fetchCount >>= (`shouldBe` 0)
                (added, removed) <- concurrently
                    (addFeedbackVote feedback.id author.id)
                    (removeFeedbackVote feedback.id author.id)
                added `shouldSatisfy` isRight
                count <- query @FeedbackVote |> fetchCount
                case removed of
                    Right () -> count `shouldBe` 0
                    Left FeedbackVoteNotFound -> count `shouldBe` 1
                    other -> expectationFailure (cs (show other))

        it "converges publish and archive races on lifecycle vote invariants" $ withContext do
            withCleanDb do
                (feedback, _, moderator) <- privateFeedbackFixture
                voter <- createUserRecord "feedback-race-voter@example.com" "staff" True
                now <- getCurrentTime

                (firstPublish, secondPublish) <- concurrently
                    (publishFeedback feedback.id moderator.id now)
                    (publishFeedback feedback.id moderator.id now)
                length [() | Right _ <- [firstPublish, secondPublish]] `shouldBe` 1
                query @FeedbackVote |> fetchCount >>= (`shouldBe` 1)

                (archiveResult, voteResult) <- concurrently
                    (archiveFeedback feedback.id moderator.id (addUTCTime 60 now))
                    (addFeedbackVote feedback.id voter.id)
                archiveResult `shouldSatisfy` either (const False) ((== Archived) . (.lifecycle))
                voteResult `shouldSatisfy` either (== FeedbackInvalidTransition) (const True)
                persisted <- fetch feedback.id
                persisted.lifecycle `shouldBe` Archived
                query @FeedbackVote |> fetchCount >>= (`shouldBe` 0)

                Right _ <- restoreFeedback feedback.id
                Right _ <- publishFeedback feedback.id moderator.id (addUTCTime 120 now)
                query @FeedbackVote
                    |> filterWhere (#feedbackItemId, unpackId feedback.id)
                    |> fetch
                    >>= deleteRecords
                let directArchive = Exception.try (withTransaction do
                        sqlExecDiscardResult
                            "UPDATE user_feedback_items SET lifecycle = 'archived', archived_at = ?, archived_by_user_id = ? WHERE id = ?"
                            (addUTCTime 180 now, unpackId moderator.id, unpackId feedback.id)) :: IO (Either Exception.SomeException ())
                let directVote = Exception.try (withTransaction do
                        sqlExecDiscardResult
                            "INSERT INTO feedback_votes (feedback_item_id, user_id) VALUES (?, ?)"
                            (unpackId feedback.id, unpackId voter.id)) :: IO (Either Exception.SomeException ())
                (directArchiveResult, directVoteResult) <- concurrently directArchive directVote
                length (filter isRight [directArchiveResult, directVoteResult]) `shouldBe` 1
                directlyPersisted <- fetch feedback.id
                directVoteCount <- query @FeedbackVote |> fetchCount
                ((directlyPersisted.lifecycle == Archived && directVoteCount == 0)
                    || (directlyPersisted.lifecycle == Public && directVoteCount == 1)) `shouldBe` True

        it "rejects ineligible and duplicate durable vote state at the database boundary" $ withContext do
            withCleanDb do
                (feedback, submitter, moderator) <- privateFeedbackFixture
                directPrivateVote <- Exception.try (newRecord @FeedbackVote
                    |> set #feedbackItemId (unpackId feedback.id)
                    |> set #userId (unpackId moderator.id)
                    |> createRecord) :: IO (Either Exception.SomeException FeedbackVote)
                directPrivateVote `shouldSatisfy` isLeft

                now <- getCurrentTime
                Right published <- publishFeedback feedback.id moderator.id now
                duplicateVote <- Exception.try (newRecord @FeedbackVote
                    |> set #feedbackItemId (unpackId feedback.id)
                    |> set #userId (unpackId submitter.id)
                    |> createRecord) :: IO (Either Exception.SomeException FeedbackVote)
                duplicateVote `shouldSatisfy` isLeft

                invalidLifecycle <- Exception.try (published
                    |> set #publishedAt Nothing
                    |> updateRecord) :: IO (Either Exception.SomeException UserFeedbackItem)
                invalidLifecycle `shouldSatisfy` isLeft

        it "validates editorial bounds and preserves votes while editing public feedback" $ withContext do
            withCleanDb do
                (feedback, _, moderator) <- privateFeedbackFixture
                now <- getCurrentTime
                Right _ <- publishFeedback feedback.id moderator.id now
                updateFeedbackEditorial feedback.id "  Better title  " "  Better description  " Suggestion
                    >>= (`shouldSatisfy` either (const False) (\item -> item.title == "Better title" && item.content == "Better description"))
                query @FeedbackVote |> fetchCount >>= (`shouldBe` 1)
                updateFeedbackEditorial feedback.id "" "valid description" Bug `shouldReturn` Left FeedbackInvalidTitle
                updateFeedbackEditorial feedback.id "Valid" "x" Bug `shouldReturn` Left FeedbackInvalidContent

    describe "Feedback lifecycle migration" do
        it "preserves predecessor rows privately and backfills deterministic titles" $ withContext do
            predecessor <- TextIO.readFile "Test/Fixtures/feedback/pre-lifecycle-schema.sql"
            migration <- TextIO.readFile "Application/Migration/1788600000-add-feedback-lifecycle-and-votes.sql"
            sqlExecDiscardResult "DROP SCHEMA IF EXISTS feedback_migration_503 CASCADE" ()
            withTransaction do
                sqlExecDiscardResult "CREATE SCHEMA feedback_migration_503" ()
                sqlExecDiscardResult "SET LOCAL search_path TO feedback_migration_503, public" ()
                case transactionRunner ?modelContext of
                    Nothing -> error "Feedback migration fixture requires a transaction runner"
                    Just runner -> do
                        runInTransaction runner (HasqlSession.script predecessor)
                        before :: [Only Text] <- sqlQuery "SELECT to_jsonb(item)::text FROM user_feedback_items item ORDER BY id" ()
                        runInTransaction runner (HasqlSession.script migration)
                        after :: [Only Text] <- sqlQuery "SELECT (to_jsonb(item) - ARRAY['title','lifecycle','published_at','published_by_user_id','archived_at','archived_by_user_id'])::text FROM user_feedback_items item ORDER BY id" ()
                        after `shouldBe` before
                rows :: [(Text, Text, Text, Text, Maybe Text)] <- sqlQuery
                    "SELECT title, lifecycle::text, content, status, submitted_path FROM user_feedback_items ORDER BY id"
                    ()
                rows `shouldBe`
                    [ ("First retained line", "private", "  \n First retained line  \nmore", "done", Just "/legacy")
                    , ("Untitled feedback", "private", " \n\t", "new", Nothing)
                    , ("Untitled feedback", "private", "\f\f\f", "triaged", Nothing)
                    , (Text.replicate 120 "界", "private", Text.replicate 130 "界", "new", Nothing)
                    ]
                sqlExecDiscardResult "SET LOCAL search_path TO public" ()
                sqlExecDiscardResult "DROP SCHEMA feedback_migration_503 CASCADE" ()

privateFeedbackFixture :: (?modelContext :: ModelContext) => IO (UserFeedbackItem, User, User)
privateFeedbackFixture = do
    venue <- createVenueWithConfig "Feedback Domain Venue"
    submitter <- createUserRecord "feedback-submitter@example.com" "staff" True
    moderator <- createUserRecordWithPlatformRole "feedback-moderator@example.com" "staff" (Just SuperAdmin) True
    feedback <- newRecord @UserFeedbackItem
        |> set #venueId (unpackId venue.id)
        |> set #submittedByUserId (unpackId submitter.id)
        |> set #title "Private feedback"
        |> set #feedbackType Bug
        |> set #lifecycle Private
        |> set #content "Private feedback description"
        |> createRecord
    pure (feedback, submitter, moderator)

voteOutcome :: Either FeedbackMutationError FeedbackVote -> Text
voteOutcome (Right _)                   = "created"
voteOutcome (Left FeedbackAlreadyVoted) = "duplicate"
voteOutcome other                       = "unexpected:" <> tshow other

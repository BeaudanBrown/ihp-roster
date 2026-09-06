module Application.Feedback.Domain
    ( FeedbackMutationError (..)
    , addFeedbackVote
    , archiveFeedback
    , deriveFeedbackTitle
    , publishFeedback
    , removeFeedbackVote
    , restoreFeedback
    , updateFeedbackEditorial
    ) where

import qualified Data.Text as Text
import qualified Database.PostgreSQL.Simple as PG
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlQuery, unpackId, withTransaction)

-- Authority checks belong to the calling controller. This module owns the
-- persisted lifecycle state machine and serializes every item mutation.
data FeedbackMutationError
    = FeedbackNotFound
    | FeedbackInvalidTransition
    | FeedbackInvalidTitle
    | FeedbackInvalidContent
    | FeedbackAlreadyVoted
    | FeedbackVoteNotFound
    deriving (Eq, Show)

publishFeedback :: (?modelContext :: ModelContext) => Id UserFeedbackItem -> Id User -> UTCTime -> IO (Either FeedbackMutationError UserFeedbackItem)
publishFeedback feedbackId actorId publishedAt =
    withLockedFeedback feedbackId \feedback ->
        if feedback.lifecycle /= Private
            then pure (Left FeedbackInvalidTransition)
            else do
                published <- feedback
                    |> set #lifecycle Public
                    |> set #publishedAt (Just publishedAt)
                    |> set #publishedByUserId (Just (unpackId actorId))
                    |> set #archivedAt Nothing
                    |> set #archivedByUserId Nothing
                    |> updateRecord
                _ <- newRecord @FeedbackVote
                    |> set #feedbackItemId (unpackId feedback.id)
                    |> set #userId feedback.submittedByUserId
                    |> createRecord
                pure (Right published)

archiveFeedback :: (?modelContext :: ModelContext) => Id UserFeedbackItem -> Id User -> UTCTime -> IO (Either FeedbackMutationError UserFeedbackItem)
archiveFeedback feedbackId actorId archivedAt =
    withLockedFeedback feedbackId \feedback ->
        if feedback.lifecycle == Archived
            then pure (Left FeedbackInvalidTransition)
            else do
                query @FeedbackVote
                    |> filterWhere (#feedbackItemId, unpackId feedback.id)
                    |> fetch
                    >>= deleteRecords
                archived <- feedback
                    |> set #lifecycle Archived
                    |> set #archivedAt (Just archivedAt)
                    |> set #archivedByUserId (Just (unpackId actorId))
                    |> updateRecord
                pure (Right archived)

restoreFeedback :: (?modelContext :: ModelContext) => Id UserFeedbackItem -> IO (Either FeedbackMutationError UserFeedbackItem)
restoreFeedback feedbackId =
    withLockedFeedback feedbackId \feedback ->
        if feedback.lifecycle /= Archived
            then pure (Left FeedbackInvalidTransition)
            else do
                restored <- feedback
                    |> set #lifecycle Private
                    |> set #publishedAt Nothing
                    |> set #publishedByUserId Nothing
                    |> set #archivedAt Nothing
                    |> set #archivedByUserId Nothing
                    |> updateRecord
                pure (Right restored)

updateFeedbackEditorial :: (?modelContext :: ModelContext) => Id UserFeedbackItem -> Text -> Text -> FeedbackTypeEnum -> IO (Either FeedbackMutationError UserFeedbackItem)
updateFeedbackEditorial feedbackId rawTitle rawContent feedbackType =
    case validateEditorial rawTitle rawContent of
        Left validationError -> pure (Left validationError)
        Right (title, content) ->
            withLockedFeedback feedbackId \feedback ->
                if feedback.lifecycle == Archived
                    then pure (Left FeedbackInvalidTransition)
                    else Right <$> (feedback
                        |> set #title title
                        |> set #content content
                        |> set #feedbackType feedbackType
                        |> updateRecord)

addFeedbackVote :: (?modelContext :: ModelContext) => Id UserFeedbackItem -> Id User -> IO (Either FeedbackMutationError FeedbackVote)
addFeedbackVote feedbackId userId =
    withLockedFeedback feedbackId \feedback ->
        if feedback.lifecycle /= Public
            then pure (Left FeedbackInvalidTransition)
            else do
                existing <- query @FeedbackVote
                    |> filterWhere (#feedbackItemId, unpackId feedback.id)
                    |> filterWhere (#userId, unpackId userId)
                    |> fetchOneOrNothing
                case existing of
                    Just _ -> pure (Left FeedbackAlreadyVoted)
                    Nothing -> Right <$> (newRecord @FeedbackVote
                        |> set #feedbackItemId (unpackId feedback.id)
                        |> set #userId (unpackId userId)
                        |> createRecord)

removeFeedbackVote :: (?modelContext :: ModelContext) => Id UserFeedbackItem -> Id User -> IO (Either FeedbackMutationError ())
removeFeedbackVote feedbackId userId =
    withLockedFeedback feedbackId \feedback ->
        if feedback.lifecycle /= Public
            then pure (Left FeedbackInvalidTransition)
            else do
                existing <- query @FeedbackVote
                    |> filterWhere (#feedbackItemId, unpackId feedback.id)
                    |> filterWhere (#userId, unpackId userId)
                    |> fetchOneOrNothing
                case existing of
                    Nothing -> pure (Left FeedbackVoteNotFound)
                    Just vote -> do
                        deleteRecord vote
                        pure (Right ())

-- QueryBuilder cannot express SELECT FOR UPDATE. Locking the parent row is the
-- single concurrency primitive: publish/archive/restore/vote races converge on
-- the lifecycle observed after the preceding transaction commits.
withLockedFeedback :: (?modelContext :: ModelContext) => Id UserFeedbackItem -> ((?modelContext :: ModelContext) => UserFeedbackItem -> IO (Either FeedbackMutationError result)) -> IO (Either FeedbackMutationError result)
withLockedFeedback feedbackId action =
    withTransaction do
        lockedIds :: [PG.Only UUID] <- sqlQuery
            "SELECT id FROM user_feedback_items WHERE id = ? FOR UPDATE"
            (PG.Only (unpackId feedbackId))
        case lockedIds of
            [] -> pure (Left FeedbackNotFound)
            [_] -> fetch feedbackId >>= action
            _ -> error "feedback primary-key lock returned multiple rows"

validateEditorial :: Text -> Text -> Either FeedbackMutationError (Text, Text)
validateEditorial rawTitle rawContent
    | Text.null title || Text.length title > 120 = Left FeedbackInvalidTitle
    | Text.length content < 3 || Text.length content > 3000 = Left FeedbackInvalidContent
    | otherwise = Right (title, content)
  where
    title = Text.strip rawTitle
    content = Text.strip rawContent

deriveFeedbackTitle :: Text -> Text
deriveFeedbackTitle content =
    Text.take 120 $ fromMaybe "Untitled feedback" $ find (not . Text.null) $ map Text.strip $ Text.lines content

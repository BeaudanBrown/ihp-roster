module Application.Feedback.Mutations
    ( editFeedback, publishFeedback, archiveFeedback, restoreFeedback, submitFeedback
    , voteFeedback, unvoteFeedback ) where

import qualified Application.Feedback.Domain as Domain
import Application.Feedback.Notification (enqueueFeedbackNotificationJobs)
import Application.Helper.Audit
import Application.Helper.ControllerContext (authenticatedCurrentUser)
import Application.Helper.FrontendContract.Surface.Feedback.Resource
import Application.Helper.Htmx (requestAuditSourceChannel)
import Application.Helper.SurfaceResource
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import Generated.Types
import IHP.ControllerPrelude
import Web.SurfaceInvalidation (withDurableLiveMutation,
                                withDurableLiveMutationOutcome)

type FeedbackMutationContext = (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request)

submitFeedback :: FeedbackMutationContext => UserFeedbackItem -> IO (LiveMutationResult [AppJob])
submitFeedback item = withDurableLiveMutation "feedback.submit" do
    saved <- createRecord item
    jobs <- enqueueFeedbackNotificationJobs saved
    recordFeedbackAudit FeedbackSubmittedAudit saved
    pure (liveMutationResult jobs [feedbackReviewResource])

editFeedback :: FeedbackMutationContext => Id UserFeedbackItem -> Text -> Text -> FeedbackTypeEnum -> IO (LiveMutationResult (Either Domain.FeedbackMutationError UserFeedbackItem))
editFeedback itemId title content feedbackType =
    moderate FeedbackEditedAudit (Domain.updateFeedbackEditorial itemId title content feedbackType)

publishFeedback :: FeedbackMutationContext => Id UserFeedbackItem -> IO (LiveMutationResult (Either Domain.FeedbackMutationError UserFeedbackItem))
publishFeedback itemId = moderate FeedbackPublishedAudit do
    now <- getCurrentTime
    Domain.publishFeedback itemId authenticatedCurrentUser.id now

archiveFeedback :: FeedbackMutationContext => Id UserFeedbackItem -> IO (LiveMutationResult (Either Domain.FeedbackMutationError UserFeedbackItem))
archiveFeedback itemId = moderate FeedbackArchivedAudit do
    now <- getCurrentTime
    Domain.archiveFeedback itemId authenticatedCurrentUser.id now

restoreFeedback :: FeedbackMutationContext => Id UserFeedbackItem -> IO (LiveMutationResult (Either Domain.FeedbackMutationError UserFeedbackItem))
restoreFeedback itemId = moderate FeedbackRestoredAudit (Domain.restoreFeedback itemId)

-- Explicit desired-state commands make stale/repeated clicks converge rather
-- than toggling an account's vote twice. Row locks also serialize moderation.
-- The authenticated account owns the vote, never a membership or impersonated
-- identity. Replays refresh stale viewers but do not fabricate audit changes.
voteFeedback :: FeedbackMutationContext => Id UserFeedbackItem -> IO (LiveMutationResult (Either Domain.FeedbackMutationError ()))
voteFeedback itemId = mutateVote FeedbackVotedAudit Domain.FeedbackAlreadyVoted itemId
    (void <$> Domain.addFeedbackVote itemId authenticatedCurrentUser.id)

unvoteFeedback :: FeedbackMutationContext => Id UserFeedbackItem -> IO (LiveMutationResult (Either Domain.FeedbackMutationError ()))
unvoteFeedback itemId = mutateVote FeedbackUnvotedAudit Domain.FeedbackVoteNotFound itemId
    (Domain.removeFeedbackVote itemId authenticatedCurrentUser.id)

mutateVote :: FeedbackMutationContext => AuditEventType -> Domain.FeedbackMutationError -> Id UserFeedbackItem -> ((?modelContext :: ModelContext) => IO (Either Domain.FeedbackMutationError ())) -> IO (LiveMutationResult (Either Domain.FeedbackMutationError ()))
mutateVote eventType unchanged itemId mutation = withDurableLiveMutationOutcome publication do
    result <- mutation
    case result of
        Right () -> do
            fetch itemId >>= recordFeedbackAudit eventType
            pure (liveMutationResult (Right ()) [feedbackBoardResource])
        Left failure | failure == unchanged -> pure (liveMutationResult (Right ()) [feedbackBoardResource])
        Left _ -> pure (liveMutationResult result [])
  where
    publication result
        | Set.null result.liveMutationTouchedResources = Nothing
        | otherwise = Just (auditEventTypeText eventType, result.liveMutationTouchedResources)

moderate :: FeedbackMutationContext => AuditEventType -> ((?modelContext :: ModelContext) => IO (Either Domain.FeedbackMutationError UserFeedbackItem)) -> IO (LiveMutationResult (Either Domain.FeedbackMutationError UserFeedbackItem))
moderate eventType mutation = withDurableLiveMutationOutcome publication do
    result <- mutation
    case result of
        Left _ -> pure (liveMutationResult result [])
        Right item -> do
            recordFeedbackAudit eventType item
            -- A private-only edit/archive/restore must not even announce board
            -- activity to ordinary subscribers. Archive retains publication
            -- facts, so its locked result tells us whether a public card left.
            let affectsPublicBoard = item.lifecycle == Public
                    || (item.lifecycle == Archived && isJust item.publishedAt)
            pure (liveMutationResult result (feedbackReviewResource : [feedbackBoardResource | affectsPublicBoard]))
  where
    publication result
        | Set.null result.liveMutationTouchedResources = Nothing
        | otherwise = Just (auditEventTypeText eventType, result.liveMutationTouchedResources)

-- Global moderation records provenance against the submission's venue, not
-- whichever venue the founder happens to be viewing. Private text never enters
-- the audit payload or durable invalidation transport.
recordFeedbackAudit :: FeedbackMutationContext => AuditEventType -> UserFeedbackItem -> IO ()
recordFeedbackAudit eventType item = do
    _ <- recordAuditEvent item.venueId (unpackId authenticatedCurrentUser.id) eventType
        "user_feedback_items" (unpackId item.id) (Aeson.object []) requestAuditSourceChannel
    pure ()

module Application.Feedback.Mutations
    ( editFeedback, publishFeedback, archiveFeedback, restoreFeedback, submitFeedback ) where

import qualified Application.Feedback.Domain as Domain
import Application.Feedback.Notification (enqueueFeedbackNotificationJobs)
import Application.Helper.Audit
import Application.Helper.ControllerContext (authenticatedCurrentUser)
import Application.Helper.FrontendContract.Surface.Feedback.Resource
import Application.Helper.Htmx (requestAuditSourceChannel)
import Application.Helper.SurfaceResource
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import Generated.Types
import IHP.ControllerPrelude
import Web.SurfaceInvalidation (withDurableLiveMutation, withDurableLiveMutationOutcome)

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

moderate :: FeedbackMutationContext => AuditEventType -> ((?modelContext :: ModelContext) => IO (Either Domain.FeedbackMutationError UserFeedbackItem)) -> IO (LiveMutationResult (Either Domain.FeedbackMutationError UserFeedbackItem))
moderate eventType mutation = withDurableLiveMutationOutcome publication do
    result <- mutation
    case result of
        Left _ -> pure (liveMutationResult result [])
        Right item -> do
            recordFeedbackAudit eventType item
            pure (liveMutationResult result [feedbackBoardResource, feedbackReviewResource])
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

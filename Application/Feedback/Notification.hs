module Application.Feedback.Notification
    ( enqueueFeedbackNotificationJobs
    , feedbackSubmittedMailKind
    ) where

import Application.EmailDelivery
import Application.Feedback.Email (feedbackSubmittedMailKind)
import Generated.Types
import IHP.ControllerPrelude

enqueueFeedbackNotificationJobs ::
    (?modelContext :: ModelContext) =>
    UserFeedbackItem ->
    IO [AppJob]
enqueueFeedbackNotificationJobs feedbackItem = do
    recipients <-
        query @User
            |> filterWhere (#platformRole, Just SuperAdmin)
            |> filterWhere (#deactivatedAt, Nothing)
            |> orderByAsc #id
            |> fetch
    forM recipients \recipient ->
        enqueueEmailDelivery
            EmailDeliveryRequest
                { mailKind = feedbackSubmittedMailKind
                , recipientAccountId = unpackId recipient.id
                , recipientAddress = recipient.email
                , domainReferenceTable = "user_feedback_items"
                , domainReferenceId = unpackId feedbackItem.id
                , semanticEventKey = "feedback:" <> inputValue feedbackItem.id
                , requestedByUserId = Just feedbackItem.submittedByUserId
                , venueId = Just feedbackItem.venueId
                }

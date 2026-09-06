module Application.Feedback.Email
    ( feedbackSubmittedMailKind
    , loadFeedbackNotificationMail
    ) where

import Application.Helper.Mail
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (ConfigProvider)
import Web.Mail.FeedbackNotification
import Web.Routes ()
import Web.Types

feedbackSubmittedMailKind :: Text
feedbackSubmittedMailKind = "feedback_submitted_v1"

loadFeedbackNotificationMail ::
    (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) =>
    Text ->
    UUID ->
    AppMailSettings ->
    Text ->
    IO (Maybe FeedbackNotificationMail)
loadFeedbackNotificationMail recipientAddress feedbackId settings appBaseUrl = do
    maybeFeedbackItem <-
        query @UserFeedbackItem
            |> filterWhere (#id, Id feedbackId)
            |> fetchOneOrNothing
    forM maybeFeedbackItem \feedbackItem -> do
        venue <- fetch (Id feedbackItem.venueId :: Id Venue)
        submitter <- fetch (Id feedbackItem.submittedByUserId :: Id User)
        venueConfig <-
            query @VenueConfig
                |> filterWhere (#venueId, feedbackItem.venueId)
                |> fetchOne
        pure
            FeedbackNotificationMail
                { recipientAddress
                , feedbackItem
                , venue
                , submitter
                , venueTimezone = venueConfig.timezone
                , feedbackUrl = stripTrailingSlash appBaseUrl <> pathTo FeedbackAction
                , fromAddress = settings.mailFromAddress
                , replyToAddress = settings.mailReplyToAddress
                }

stripTrailingSlash :: Text -> Text
stripTrailingSlash = Text.dropWhileEnd (== '/')

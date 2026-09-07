module Web.Mail.FeedbackNotification
    ( FeedbackNotificationMail (..)
    , formatFeedbackSubmittedAt
    ) where

import Application.VenueTime
import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime)
import Generated.Types
import IHP.MailPrelude
import qualified IHP.HSX.Markup as Markup
import Web.Mail.Shared


data FeedbackNotificationMail = FeedbackNotificationMail
    { recipientAddress :: !Text
    , feedbackItem     :: !UserFeedbackItem
    , venue            :: !Venue
    , submitter        :: !User
    , venueTimezone    :: !Text
    , feedbackUrl      :: !Text
    , fromAddress      :: !Text
    , replyToAddress   :: !Text
    }

instance BuildMail FeedbackNotificationMail where
    subject = "New Bepis feedback submitted"
    to FeedbackNotificationMail { recipientAddress } = Address Nothing recipientAddress
    from = bepisFrom ?mail.fromAddress
    replyTo FeedbackNotificationMail { replyToAddress } = bepisReplyTo replyToAddress
    html mail@FeedbackNotificationMail { feedbackItem, venue, submitter, feedbackUrl } =
        [hsx|
            <h1>New Bepis feedback</h1>
            <p>A user submitted private feedback for review.</p>
            <dl>
                <dt>Type</dt><dd>{feedbackTypeLabel feedbackItem.feedbackType}</dd>
                <dt>Venue</dt><dd>{venue.name}</dd>
                <dt>Submitter</dt><dd>{submitter.email}</dd>
                {optionalHtmlField "Submission-time role" feedbackItem.submittedRole}
                <dt>Submitted</dt><dd>{formatFeedbackSubmittedAt mail.venueTimezone feedbackItem.createdAt}</dd>
                {optionalHtmlField "Page" feedbackItem.submittedPath}
                {optionalHtmlField "Browser/device" feedbackItem.userAgent}
                {optionalHtmlField "Viewport width" ((<> "px") . tshow <$> feedbackItem.viewportWidth)}
                {optionalHtmlField "Viewport height" ((<> "px") . tshow <$> feedbackItem.viewportHeight)}
                {optionalHtmlField "Device pixel ratio" (tshow <$> feedbackItem.devicePixelRatio)}
                {optionalHtmlField "Device class" feedbackItem.deviceClass}
                {optionalHtmlField "Display mode" feedbackItem.displayMode}
            </dl>
            <h2>Feedback</h2>
            <p style="white-space: pre-wrap">{feedbackItem.content}</p>
            <p><a href={feedbackUrl}>Review Bepis Feedback</a></p>
        |]
    text mail@FeedbackNotificationMail { feedbackItem, venue, submitter, feedbackUrl } =
        Text.intercalate
            "\n"
            ( [ "New Bepis feedback"
              , ""
              , "Type: " <> feedbackTypeLabel feedbackItem.feedbackType
              , "Venue: " <> venue.name
              , "Submitter: " <> submitter.email
              ]
                <> optionalLine "Submission-time role" feedbackItem.submittedRole
                <> ["Submitted: " <> formatFeedbackSubmittedAt mail.venueTimezone feedbackItem.createdAt]
                <> optionalLine "Page" feedbackItem.submittedPath
                <> optionalLine "Browser/device" feedbackItem.userAgent
                <> optionalLine "Viewport width" ((<> "px") . tshow <$> feedbackItem.viewportWidth)
                <> optionalLine "Viewport height" ((<> "px") . tshow <$> feedbackItem.viewportHeight)
                <> optionalLine "Device pixel ratio" (tshow <$> feedbackItem.devicePixelRatio)
                <> optionalLine "Device class" feedbackItem.deviceClass
                <> optionalLine "Display mode" feedbackItem.displayMode
                <> [ ""
                   , "Feedback:"
                   , feedbackItem.content
                   , ""
                   , "Review Bepis Feedback: " <> feedbackUrl
                   ]
            )

feedbackTypeLabel :: FeedbackTypeEnum -> Text
feedbackTypeLabel = \case
    Bug        -> "Bug"
    Suggestion -> "Suggestion"
    Other      -> "Other"

optionalLine :: Text -> Maybe Text -> [Text]
optionalLine label = maybe [] (\value -> [label <> ": " <> value])

optionalHtmlField :: Text -> Maybe Text -> Markup.Html
optionalHtmlField label =
    maybe mempty (\value -> [hsx|<dt>{label}</dt><dd>{value}</dd>|])

formatFeedbackSubmittedAt :: Text -> UTCTime -> Text
formatFeedbackSubmittedAt timezone submittedAt
    | timezone == melbourneTimeZoneName =
        cs (formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S" localTime)
            <> " "
            <> timezone
    | otherwise =
        cs (formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S UTC" submittedAt)
  where
    localTime = resolvedInstantLocalTime (resolvedInstantFromUTC submittedAt)

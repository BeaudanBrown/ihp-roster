module Web.Mail.Billing.Notification where

import Generated.Types
import IHP.MailPrelude
import Web.Mail.Shared

data BillingNotificationMail = BillingNotificationMail
    { recipient        :: User
    , venue            :: Venue
    , billingEvent     :: BillingEvent
    , notificationKind :: Text
    , billingUrl       :: Text
    , fromAddress      :: Text
    , replyToAddress   :: Text
    , supportEmail     :: Text
    }

instance BuildMail BillingNotificationMail where
    subject = "Billing needs attention"

    to BillingNotificationMail { recipient } =
        Address
            { addressName = Nothing
            , addressEmail = recipient.email
            }

    from = bepisFrom ?mail.fromAddress

    replyTo BillingNotificationMail { replyToAddress } = bepisReplyTo replyToAddress

    html BillingNotificationMail { venue, billingEvent, notificationKind, billingUrl, supportEmail } = [hsx|
        <p>Billing needs attention for {venue.name}.</p>
        <p>
            Event: {billingEvent.eventType}<br/>
            Status: {notificationKind}
        </p>
        <p><a href={billingUrl}>Open billing</a></p>
        <hr/>
        <p>
            You’re receiving this because this email address is associated with a Bepis account, venue, or invitation.
            If this wasn’t expected, you can ignore this email or contact {supportEmail}.
        </p>
    |]

    text BillingNotificationMail { venue, billingEvent, notificationKind, billingUrl, supportEmail } =
        "Billing needs attention for "
            <> venue.name
            <> ".\n\nEvent: "
            <> billingEvent.eventType
            <> "\nStatus: "
            <> notificationKind
            <> "\n\nOpen billing:\n"
            <> billingUrl
            <> supportFooterText supportEmail

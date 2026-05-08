module Web.Mail.Billing.Notification where

import Generated.Types
import IHP.MailPrelude

data BillingNotificationMail = BillingNotificationMail
    { recipient        :: User
    , venue            :: Venue
    , billingEvent     :: BillingEvent
    , notificationKind :: Text
    , billingUrl       :: Text
    , fromAddress      :: Text
    }

instance BuildMail BillingNotificationMail where
    subject = "Billing needs attention"

    to BillingNotificationMail { recipient } =
        Address
            { addressName = Nothing
            , addressEmail = recipient.email
            }

    from =
        Address
            { addressName = Just "Bepis"
            , addressEmail = ?mail.fromAddress
            }

    html BillingNotificationMail { venue, billingEvent, notificationKind, billingUrl } = [hsx|
        <p>Billing needs attention for {venue.name}.</p>
        <p>
            Event: {billingEvent.eventType}<br/>
            Status: {notificationKind}
        </p>
        <p><a href={billingUrl}>Open billing</a></p>
    |]

    text BillingNotificationMail { venue, billingEvent, notificationKind, billingUrl } =
        "Billing needs attention for "
            <> venue.name
            <> ".\n\nEvent: "
            <> billingEvent.eventType
            <> "\nStatus: "
            <> notificationKind
            <> "\n\nOpen billing:\n"
            <> billingUrl

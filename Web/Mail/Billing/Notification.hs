module Web.Mail.Billing.Notification where

import Application.Billing.NotificationKind
import Generated.Types
import IHP.MailPrelude
import Web.Mail.Shared

data BillingNotificationMail = BillingNotificationMail
    { recipient        :: User
    , venue            :: Venue
    , notificationKind :: BillingNotificationKind
    , sourceReference  :: Maybe Text
    , billingUrl       :: Text
    , fromAddress      :: Text
    , replyToAddress   :: Text
    , supportEmail     :: Text
    }

data BillingNotificationCopy = BillingNotificationCopy
    { copySubject :: !Text
    , copyHeading :: !Text
    , copyMessage :: !Text
    }

instance BuildMail BillingNotificationMail where
    subject = (billingNotificationCopy ?mail.notificationKind ?mail.venue.name).copySubject

    to BillingNotificationMail { recipient } =
        Address
            { addressName = Nothing
            , addressEmail = recipient.email
            }

    from = bepisFrom ?mail.fromAddress

    replyTo BillingNotificationMail { replyToAddress } = bepisReplyTo replyToAddress

    html BillingNotificationMail { venue, notificationKind, sourceReference, billingUrl, supportEmail } =
        let copy = billingNotificationCopy notificationKind venue.name
         in [hsx|
            <p>{copy.copyHeading}</p>
            <p>{copy.copyMessage}</p>
            <p>{maybe "" ("Support reference: " <>) sourceReference}</p>
            <p><a href={billingUrl}>Open billing</a></p>
            <hr/>
            <p>
                You’re receiving this because this email address is associated with a Bepis account or venue.
                If this wasn’t expected, you can ignore this email or contact {supportEmail}.
            </p>
        |]

    text BillingNotificationMail { venue, notificationKind, sourceReference, billingUrl, supportEmail } =
        let copy = billingNotificationCopy notificationKind venue.name
         in copy.copyHeading
                <> "\n\n"
                <> copy.copyMessage
                <> maybe "" ("\n\nSupport reference: " <>) sourceReference
                <> "\n\nOpen billing:\n"
                <> billingUrl
                <> supportFooterText supportEmail

billingNotificationCopy :: BillingNotificationKind -> Text -> BillingNotificationCopy
billingNotificationCopy notificationKind venueName =
    case notificationKind of
        BillingPaymentTrouble ->
            BillingNotificationCopy
                { copySubject = "Billing needs attention"
                , copyHeading = "Billing needs attention for " <> venueName <> "."
                , copyMessage = "Stripe reported a subscription payment problem. Open Billing to review the subscription and manage payment details securely through Stripe."
                }
        BillingPaymentRecovered ->
            BillingNotificationCopy
                { copySubject = "Billing is back to normal"
                , copyHeading = "Billing is back to normal for " <> venueName <> "."
                , copyMessage = "Stripe reported that the subscription has recovered and is active again."
                }
        BillingCancellationScheduled ->
            BillingNotificationCopy
                { copySubject = "Subscription cancellation scheduled"
                , copyHeading = "Subscription cancellation is scheduled for " <> venueName <> "."
                , copyMessage = "Stripe reported that the subscription is scheduled to cancel at the end of its current billing period."
                }
        BillingRenewalResumed ->
            BillingNotificationCopy
                { copySubject = "Subscription will renew"
                , copyHeading = "The subscription will continue for " <> venueName <> "."
                , copyMessage = "Stripe reported that the scheduled cancellation was reversed. The subscription will continue and renew automatically."
                }
        BillingCancellationCompleted ->
            BillingNotificationCopy
                { copySubject = "Subscription cancellation completed"
                , copyHeading = "Subscription cancellation is complete for " <> venueName <> "."
                , copyMessage = "Stripe reported that the subscription has been canceled."
                }
        BillingCheckoutPaymentFailed ->
            BillingNotificationCopy
                { copySubject = "Checkout payment needs attention"
                , copyHeading = "Checkout payment needs attention for " <> venueName <> "."
                , copyMessage = "Stripe reported that the Checkout payment did not complete. Open Billing to try again or review the subscription."
                }
        BillingOperationalRetriesExhausted ->
            BillingNotificationCopy
                { copySubject = "Billing recovery needs support attention"
                , copyHeading = "Billing recovery needs support attention for " <> venueName <> "."
                , copyMessage = "An automated billing recovery operation exhausted its retries. Review the founder billing diagnostics; no provider error details are included in this email."
                }

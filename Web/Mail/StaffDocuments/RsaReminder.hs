module Web.Mail.StaffDocuments.RsaReminder where

import qualified Data.Text as Text
import Generated.Types
import IHP.MailPrelude
import Web.Mail.Shared

data RsaReminderMail = RsaReminderMail
    { recipientAddress :: Text
    , recipientName    :: Text
    , venue            :: Venue
    , staff            :: Staff
    , staffDocument    :: StaffDocument
    , reminderSubject  :: Text
    , reminderIntro    :: Text
    , fromAddress      :: Text
    , replyToAddress   :: Text
    , supportEmail     :: Text
    }

instance BuildMail RsaReminderMail where
    subject = ?mail.reminderSubject

    to RsaReminderMail { recipientAddress, recipientName } =
        Address
            { addressName = Just recipientName
            , addressEmail = recipientAddress
            }

    from = bepisFrom ?mail.fromAddress

    replyTo RsaReminderMail { replyToAddress } = bepisReplyTo replyToAddress

    html RsaReminderMail { venue, staff, staffDocument, reminderIntro, supportEmail } = [hsx|
        <p>{reminderIntro}</p>
        <p>
            Venue: {venue.name}<br/>
            Staff member: {staffDisplayName staff}<br/>
            Expiry date: {tshow staffDocument.expiryDate}
        </p>
        <p>Please upload a current RSA document in your Bepis profile.</p>
        <hr/>
        <p>
            You’re receiving this because this email address is associated with a Bepis account, venue, or invitation.
            If this wasn’t expected, you can ignore this email or contact {supportEmail}.
        </p>
    |]

    text RsaReminderMail { venue, staff, staffDocument, reminderIntro, supportEmail } =
        reminderIntro
            <> "\n\nVenue: "
            <> venue.name
            <> "\nStaff member: "
            <> staffDisplayName staff
            <> "\nExpiry date: "
            <> tshow staffDocument.expiryDate
            <> "\n\nPlease upload a current RSA document in your Bepis profile."
            <> supportFooterText supportEmail

staffDisplayName :: Staff -> Text
staffDisplayName staff =
    Text.strip (staff.firstName <> " " <> staff.lastName)

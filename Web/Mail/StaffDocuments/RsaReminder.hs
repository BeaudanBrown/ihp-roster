module Web.Mail.StaffDocuments.RsaReminder where

import qualified Data.Text as Text
import Generated.Types
import IHP.MailPrelude

data RsaReminderMail = RsaReminderMail
    { recipient       :: User
    , venue           :: Venue
    , staff           :: Staff
    , staffDocument   :: StaffDocument
    , reminderSubject :: Text
    , reminderIntro   :: Text
    , fromAddress     :: Text
    }

instance BuildMail RsaReminderMail where
    subject = ?mail.reminderSubject

    to RsaReminderMail { recipient, staff } =
        Address
            { addressName = Just (staffDisplayName staff)
            , addressEmail = recipient.email
            }

    from =
        Address
            { addressName = Just "Bepis"
            , addressEmail = ?mail.fromAddress
            }

    html RsaReminderMail { venue, staff, staffDocument, reminderIntro } = [hsx|
        <p>{reminderIntro}</p>
        <p>
            Venue: {venue.name}<br/>
            Staff member: {staffDisplayName staff}<br/>
            Expiry date: {tshow staffDocument.expiryDate}
        </p>
        <p>Please upload a current RSA document in your profile.</p>
    |]

    text RsaReminderMail { venue, staff, staffDocument, reminderIntro } =
        reminderIntro
            <> "\n\nVenue: "
            <> venue.name
            <> "\nStaff member: "
            <> staffDisplayName staff
            <> "\nExpiry date: "
            <> tshow staffDocument.expiryDate
            <> "\n\nPlease upload a current RSA document in your profile."

staffDisplayName :: Staff -> Text
staffDisplayName staff =
    Text.strip (staff.firstName <> " " <> staff.lastName)

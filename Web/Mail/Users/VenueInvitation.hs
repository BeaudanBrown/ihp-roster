module Web.Mail.Users.VenueInvitation where

import Application.VenueRole (parseVenueRole, venueRoleMailLabel)
import Generated.Types
import IHP.MailPrelude
import Web.Mail.Shared

data VenueInvitationMail = VenueInvitationMail
    { invitation       :: VenueInvitation
    , recipientAddress :: Text
    , venue            :: Venue
    , inviteUrl        :: Text
    , fromAddress      :: Text
    , replyToAddress   :: Text
    , supportEmail     :: Text
    }

instance BuildMail VenueInvitationMail where
    subject = "You're invited to join " <> ?mail.venue.name <> " on Bepis"

    to VenueInvitationMail { recipientAddress } =
        Address
            { addressName = Nothing
            , addressEmail = recipientAddress
            }

    from = bepisFrom ?mail.fromAddress

    replyTo VenueInvitationMail { replyToAddress } = bepisReplyTo replyToAddress

    html VenueInvitationMail { invitation, venue, inviteUrl, supportEmail } = [hsx|
        <p>{venueInvitationMailIntro invitation venue}</p>
        <p>Bepis helps venues manage rosters, availability, timesheets, and staff details.</p>
        <p><a href={inviteUrl}>Accept invitation</a></p>
        <p>This invitation expires in 24 hours.</p>
        <hr/>
        <p>
            You’re receiving this because this email address is associated with a Bepis account, venue, or invitation.
            If this wasn’t expected, you can ignore this email or contact {supportEmail}.
        </p>
    |]

    text VenueInvitationMail { invitation, venue, inviteUrl, supportEmail } =
        venueInvitationMailIntro invitation venue
            <> "\n\nBepis helps venues manage rosters, availability, timesheets, and staff details."
            <> "\n\nAccept invitation:\n"
            <> inviteUrl
            <> "\n\nThis invitation expires in 24 hours."
            <> supportFooterText supportEmail

venueInvitationMailIntro :: VenueInvitation -> Venue -> Text
venueInvitationMailIntro invitation venue
    | isJust invitation.staffId = "You’ve been invited to claim your Bepis staff profile for " <> venue.name <> " and create your account."
    | otherwise = "You’ve been invited to join " <> venue.name <> " on Bepis as " <> venueRoleMailLabel invitation.inviteRole <> "."

inviteRoleLabel :: Text -> Text
inviteRoleLabel value = maybe "worker" venueRoleMailLabel (parseVenueRole value)

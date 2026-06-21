module Web.Mail.Users.VenueInvitation where

import Generated.Types
import IHP.MailPrelude
import Web.Mail.Shared

data VenueInvitationMail = VenueInvitationMail
    { invitation     :: VenueInvitation
    , venue          :: Venue
    , inviteUrl      :: Text
    , fromAddress    :: Text
    , replyToAddress :: Text
    , supportEmail   :: Text
    }

instance BuildMail VenueInvitationMail where
    subject = "You're invited to join " <> ?mail.venue.name <> " on Bepis"

    to VenueInvitationMail { invitation } =
        Address
            { addressName = Nothing
            , addressEmail = invitation.email
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
    | otherwise = "You’ve been invited to join " <> venue.name <> " on Bepis as " <> inviteRoleLabel invitation.inviteRole <> "."

inviteRoleLabel :: InputValue value => value -> Text
inviteRoleLabel value =
    case inputValue value of
        "venue_owner" -> "venue owner"
        "venue_admin" -> "venue admin"
        "manager"     -> "manager"
        "supervisor"  -> "supervisor"
        _             -> "worker"

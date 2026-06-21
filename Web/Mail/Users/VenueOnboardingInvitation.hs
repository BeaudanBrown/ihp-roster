module Web.Mail.Users.VenueOnboardingInvitation where

import Generated.Types
import IHP.MailPrelude
import Web.Mail.Shared

data VenueOnboardingInvitationMail = VenueOnboardingInvitationMail
    { invitation     :: VenueOnboardingInvitation
    , inviteUrl      :: Text
    , fromAddress    :: Text
    , replyToAddress :: Text
    , supportEmail   :: Text
    }

instance BuildMail VenueOnboardingInvitationMail where
    subject = "Create your Bepis venue"

    to VenueOnboardingInvitationMail { invitation } =
        Address
            { addressName = Nothing
            , addressEmail = invitation.email
            }

    from = bepisFrom ?mail.fromAddress

    replyTo VenueOnboardingInvitationMail { replyToAddress } = bepisReplyTo replyToAddress

    html VenueOnboardingInvitationMail { inviteUrl, supportEmail } = [hsx|
        <p>You’ve been invited to create and configure a venue in Bepis.</p>
        <p>Bepis helps venues manage rosters, availability, timesheets, and staff details.</p>
        <p><a href={inviteUrl}>Create your account and set up your venue</a></p>
        <p>This invitation expires in 24 hours.</p>
        <hr/>
        <p>
            You’re receiving this because this email address is associated with a Bepis account, venue, or invitation.
            If this wasn’t expected, you can ignore this email or contact {supportEmail}.
        </p>
    |]

    text VenueOnboardingInvitationMail { inviteUrl, supportEmail } =
        "You’ve been invited to create and configure a venue in Bepis."
            <> "\n\nBepis helps venues manage rosters, availability, timesheets, and staff details."
            <> "\n\nCreate your account and set up your venue:\n"
            <> inviteUrl
            <> "\n\nThis invitation expires in 24 hours."
            <> supportFooterText supportEmail

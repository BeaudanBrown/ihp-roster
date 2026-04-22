module Web.Mail.Users.VenueOnboardingInvitation where

import Generated.Types
import IHP.MailPrelude

data VenueOnboardingInvitationMail = VenueOnboardingInvitationMail
    { invitation  :: VenueOnboardingInvitation
    , inviteUrl   :: Text
    , fromAddress :: Text
    }

instance BuildMail VenueOnboardingInvitationMail where
    subject = "Create your Bepis venue"

    to VenueOnboardingInvitationMail { invitation } =
        Address
            { addressName = Nothing
            , addressEmail = invitation.email
            }

    from =
        Address
            { addressName = Just "Bepis"
            , addressEmail = ?mail.fromAddress
            }

    html VenueOnboardingInvitationMail { inviteUrl } = [hsx|
        <p>You have been invited to create and configure a new venue in Bepis.</p>
        <p><a href={inviteUrl}>Create your account and set up your venue</a></p>
        <p>This invitation expires in 24 hours.</p>
    |]

    text VenueOnboardingInvitationMail { inviteUrl } =
        "You have been invited to create and configure a new venue in Bepis.\n\nCreate your account and set up your venue:\n"
            <> inviteUrl
            <> "\n\nThis invitation expires in 24 hours."

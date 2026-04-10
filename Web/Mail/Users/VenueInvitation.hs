module Web.Mail.Users.VenueInvitation where

import Generated.Types
import IHP.MailPrelude

data VenueInvitationMail = VenueInvitationMail
    { invitation  :: VenueInvitation
    , inviteUrl   :: Text
    , fromAddress :: Text
    }

instance BuildMail VenueInvitationMail where
    subject = "You're invited to join Bepis"

    to VenueInvitationMail { invitation } =
        Address
            { addressName = Nothing
            , addressEmail = invitation.email
            }

    from =
        Address
            { addressName = Just "Bepis"
            , addressEmail = ?mail.fromAddress
            }

    html VenueInvitationMail { invitation, inviteUrl } = [hsx|
        <p>You have been invited to join this venue as {inviteRoleLabel invitation.inviteRole}.</p>
        <p><a href={inviteUrl}>Accept invitation</a></p>
        <p>This invitation expires in 24 hours.</p>
    |]

    text VenueInvitationMail { invitation, inviteUrl } =
        "You have been invited to join this venue as "
            <> inviteRoleLabel invitation.inviteRole
            <> ".\n\nAccept invitation:\n"
            <> inviteUrl
            <> "\n\nThis invitation expires in 24 hours."

inviteRoleLabel :: InputValue value => value -> Text
inviteRoleLabel value =
    case inputValue value of
        "venue_owner" -> "venue owner"
        "venue_admin" -> "venue admin"
        "manager"     -> "manager"
        _             -> "worker"

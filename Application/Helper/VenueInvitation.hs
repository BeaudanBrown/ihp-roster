module Application.Helper.VenueInvitation where

import Application.Helper.EmailVerification (isEmailDeliveryDisabled)
import Application.Helper.View (appendQueryParams)
import IHP.EnvVar
import IHP.Mail
import Web.Controller.Prelude
import Web.Mail.Users.VenueInvitation
import Web.Types

venueInvitationLifetime :: NominalDiffTime
venueInvitationLifetime = 60 * 60 * 24

venueInvitationUrl :: Text -> VenueInvitation -> Text
venueInvitationUrl appBaseUrl invitation =
    appBaseUrl <> appendQueryParams (pathTo NewUserAction) [("invitationId", tshow invitation.id)]

sendVenueInvitationEmail :: (?context :: ControllerContext, ?modelContext :: ModelContext) => VenueInvitation -> IO ()
sendVenueInvitationEmail invitation = do
    fromAddress :: Text <- envOrDefault "MAIL_FROM" "noreply@dev.local"
    appBaseUrl :: Text <- envOrDefault "APP_BASE_URL" "http://localhost:8000"
    emailDeliveryDisabled <- isEmailDeliveryDisabled
    unless emailDeliveryDisabled do
        sendMail VenueInvitationMail
            { invitation = invitation
            , inviteUrl = venueInvitationUrl appBaseUrl invitation
            , fromAddress = fromAddress
            }

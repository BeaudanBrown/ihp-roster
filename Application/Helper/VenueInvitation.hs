module Application.Helper.VenueInvitation where

import Application.Helper.EmailVerification (isEmailDeliveryDisabled)
import Application.Helper.View (appendQueryParams)
import qualified Control.Exception.Safe as Exception
import IHP.EnvVar
import IHP.FrameworkConfig (ConfigProvider)
import IHP.Mail
import Web.Controller.Prelude
import Web.Mail.Users.VenueInvitation
import Web.Types

venueInvitationLifetime :: NominalDiffTime
venueInvitationLifetime = 60 * 60 * 24

venueInvitationUrl :: Text -> VenueInvitation -> Text
venueInvitationUrl appBaseUrl invitation =
    appBaseUrl <> appendQueryParams (pathTo NewUserAction) [("invitationId", tshow invitation.id)]

sendVenueInvitationEmail :: (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) => VenueInvitation -> IO ()
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

deliverVenueInvitationEmail :: (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) => VenueInvitation -> IO (Either Text VenueInvitation)
deliverVenueInvitationEmail invitation = do
    result <- Exception.tryAny (sendVenueInvitationEmail invitation)
    now <- getCurrentTime
    case result of
        Right () ->
            Right <$>
                ( invitation
                    |> set #deliveryStatus (unsafeEnumFromText @InvitationDeliveryStatusEnum "sent")
                    |> set #deliveryError Nothing
                    |> set #deliveredAt (Just now)
                    |> updateRecord
                )
        Left exception -> do
            let errorMessage = cs (displayException exception)
            _ <-
                invitation
                    |> set #deliveryStatus (unsafeEnumFromText @InvitationDeliveryStatusEnum "failed")
                    |> set #deliveryError (Just errorMessage)
                    |> updateRecord
            pure (Left errorMessage)

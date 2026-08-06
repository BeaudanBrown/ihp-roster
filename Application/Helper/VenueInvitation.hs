module Application.Helper.VenueInvitation where

import Application.Helper.EmailVerification (isEmailDeliveryDisabled)
import Application.Helper.InvitationStatus (invitationStatusAllowsRenewal)
import Application.Helper.Mail
import Application.Helper.Url (appendQueryParams)
import qualified Control.Exception.Safe as Exception
import IHP.EnvVar
import IHP.FrameworkConfig (ConfigProvider)
import IHP.Mail
import Web.Controller.Prelude
import Web.Mail.Users.VenueInvitation
import Web.Types

venueInvitationLifetime :: NominalDiffTime
venueInvitationLifetime = 60 * 60 * 24 * 14

venueInvitationEffectiveExpiresAt :: VenueInvitation -> UTCTime
venueInvitationEffectiveExpiresAt invitation =
    fromMaybe (addUTCTime venueInvitationLifetime invitation.createdAt) invitation.expiresAt

venueInvitationIsActive :: UTCTime -> VenueInvitation -> Bool
venueInvitationIsActive now invitation =
    invitationStatusAllowsRenewal invitation.status
        && isNothing invitation.acceptedAt
        && venueInvitationEffectiveExpiresAt invitation > now

venueInvitationUrl :: Text -> VenueInvitation -> Text
venueInvitationUrl appBaseUrl invitation =
    appBaseUrl <> appendQueryParams (pathTo NewUserAction) [("invitationId", tshow invitation.id)]

sendVenueInvitationEmail :: (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) => VenueInvitation -> IO ()
sendVenueInvitationEmail invitation = do
    AppMailSettings { .. } <- loadAppMailSettings
    appBaseUrl :: Text <- envOrDefault "APP_BASE_URL" "http://localhost:8000"
    venue <- fetch (Id invitation.venueId :: Id Venue)
    emailDeliveryDisabled <- isEmailDeliveryDisabled
    unless emailDeliveryDisabled do
        sendMail VenueInvitationMail
            { invitation = invitation
            , venue = venue
            , inviteUrl = venueInvitationUrl appBaseUrl invitation
            , fromAddress = mailFromAddress
            , replyToAddress = mailReplyToAddress
            , supportEmail = mailSupportEmail
            }

deliverVenueInvitationEmail :: (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) => VenueInvitation -> IO (Either Text VenueInvitation)
deliverVenueInvitationEmail invitation = do
    result <- Exception.tryAny (sendVenueInvitationEmail invitation)
    now <- getCurrentTime
    case result of
        Right () ->
            Right <$>
                ( invitation
                    |> set #deliveryStatus (Sent)
                    |> set #deliveryError Nothing
                    |> set #deliveredAt (Just now)
                    |> updateRecord
                )
        Left exception -> do
            let errorMessage = cs (displayException exception)
            _ <-
                invitation
                    |> set #deliveryStatus (Failed)
                    |> set #deliveryError (Just errorMessage)
                    |> updateRecord
            pure (Left errorMessage)

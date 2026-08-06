module Application.Helper.VenueOnboardingInvitation where

import Application.Helper.EmailVerification (isEmailDeliveryDisabled)
import Application.Helper.InvitationStatus (invitationStatusAllowsRenewal)
import Application.Helper.Mail
import Application.Helper.Url (appendQueryParams)
import qualified Control.Exception.Safe as Exception
import IHP.EnvVar
import IHP.FrameworkConfig (ConfigProvider)
import IHP.Mail
import Web.Controller.Prelude
import Web.Mail.Users.VenueOnboardingInvitation
import Web.Types

venueOnboardingInvitationLifetime :: NominalDiffTime
venueOnboardingInvitationLifetime = 60 * 60 * 24 * 14

venueOnboardingInvitationUrl :: Text -> VenueOnboardingInvitation -> Text
venueOnboardingInvitationUrl appBaseUrl invitation =
    appBaseUrl <> appendQueryParams (pathTo NewVenueOnboardingUserAction) [("invitationId", tshow invitation.id)]

venueOnboardingInvitationIsActive :: UTCTime -> VenueOnboardingInvitation -> Bool
venueOnboardingInvitationIsActive now invitation =
    invitationStatusAllowsRenewal invitation.status
        && isNothing invitation.acceptedAt
        && maybe True (> now) invitation.expiresAt

sendVenueOnboardingInvitationEmail :: (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) => VenueOnboardingInvitation -> IO ()
sendVenueOnboardingInvitationEmail invitation = do
    AppMailSettings { .. } <- loadAppMailSettings
    appBaseUrl :: Text <- envOrDefault "APP_BASE_URL" "http://localhost:8000"
    emailDeliveryDisabled <- isEmailDeliveryDisabled
    unless emailDeliveryDisabled do
        sendMail VenueOnboardingInvitationMail
            { invitation = invitation
            , inviteUrl = venueOnboardingInvitationUrl appBaseUrl invitation
            , fromAddress = mailFromAddress
            , replyToAddress = mailReplyToAddress
            , supportEmail = mailSupportEmail
            }

deliverVenueOnboardingInvitationEmail :: (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) => VenueOnboardingInvitation -> IO (Either Text VenueOnboardingInvitation)
deliverVenueOnboardingInvitationEmail invitation = do
    result <- Exception.tryAny (sendVenueOnboardingInvitationEmail invitation)
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

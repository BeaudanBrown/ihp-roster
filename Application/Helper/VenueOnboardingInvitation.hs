module Application.Helper.VenueOnboardingInvitation where

import Application.Helper.EmailVerification (isEmailDeliveryDisabled)
import Application.Helper.View (appendQueryParams)
import qualified Control.Exception.Safe as Exception
import IHP.EnvVar
import IHP.Mail
import Web.Controller.Prelude
import Web.Mail.Users.VenueOnboardingInvitation
import Web.Types

venueOnboardingInvitationLifetime :: NominalDiffTime
venueOnboardingInvitationLifetime = 60 * 60 * 24

venueOnboardingInvitationUrl :: Text -> VenueOnboardingInvitation -> Text
venueOnboardingInvitationUrl appBaseUrl invitation =
    appBaseUrl <> appendQueryParams (pathTo NewVenueOnboardingUserAction) [("invitationId", tshow invitation.id)]

venueOnboardingInvitationIsActive :: UTCTime -> VenueOnboardingInvitation -> Bool
venueOnboardingInvitationIsActive now invitation =
    invitation.status == unsafeEnumFromText @InvitationStatusEnum "pending"
        && isNothing invitation.acceptedAt
        && maybe True (> now) invitation.expiresAt

sendVenueOnboardingInvitationEmail :: (?context :: ControllerContext, ?modelContext :: ModelContext) => VenueOnboardingInvitation -> IO ()
sendVenueOnboardingInvitationEmail invitation = do
    fromAddress :: Text <- envOrDefault "MAIL_FROM" "noreply@dev.local"
    appBaseUrl :: Text <- envOrDefault "APP_BASE_URL" "http://localhost:8000"
    emailDeliveryDisabled <- isEmailDeliveryDisabled
    unless emailDeliveryDisabled do
        sendMail VenueOnboardingInvitationMail
            { invitation = invitation
            , inviteUrl = venueOnboardingInvitationUrl appBaseUrl invitation
            , fromAddress = fromAddress
            }

deliverVenueOnboardingInvitationEmail :: (?context :: ControllerContext, ?modelContext :: ModelContext) => VenueOnboardingInvitation -> IO (Either Text VenueOnboardingInvitation)
deliverVenueOnboardingInvitationEmail invitation = do
    result <- Exception.tryAny (sendVenueOnboardingInvitationEmail invitation)
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

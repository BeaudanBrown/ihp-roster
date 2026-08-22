module Application.InvitationDelivery.Email
    ( VenueInvitationMailProjection (..)
    , VenueOnboardingInvitationMailProjection (..)
    , completeVenueInvitationEmail
    , completeVenueOnboardingInvitationEmail
    , loadVenueInvitationMail
    , loadVenueOnboardingInvitationMail
    , markInvitationDeliveryFailed
    ) where

import Application.Helper.Mail
import Application.Helper.VenueInvitation
import Application.Helper.VenueOnboardingInvitation
import Application.InvitationDelivery.Types
import Application.VenueInvitation.Mutations (withVenueInvitationLockInCurrentTransaction)
import Application.VenueOnboardingInvitation.Mutations (withVenueOnboardingInvitationLock)
import Control.Monad (void)
import Generated.Types
import IHP.ControllerPrelude
import Web.Mail.Users.VenueInvitation
import Web.Mail.Users.VenueOnboardingInvitation

data VenueInvitationMailProjection
    = VenueInvitationMailSkipped !Text
    | VenueInvitationMailReady !VenueInvitationMail

data VenueOnboardingInvitationMailProjection
    = VenueOnboardingInvitationMailSkipped !Text
    | VenueOnboardingInvitationMailReady !VenueOnboardingInvitationMail

loadVenueInvitationMail ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Text ->
    UUID ->
    Maybe UUID ->
    AppMailSettings ->
    Text ->
    IO VenueInvitationMailProjection
loadVenueInvitationMail recipientIdentityId recipientAddress invitationId jobVenueId settings appBaseUrl = do
    maybeInvitation <- query @VenueInvitation
        |> filterWhere (#id, Id invitationId)
        |> fetchOneOrNothing
    case maybeInvitation of
        Nothing -> pure (VenueInvitationMailSkipped "domain_reference_missing")
        Just invitation -> do
            now <- getCurrentTime
            if recipientIdentityId /= invitationId || recipientAddress /= invitation.email
                then pure (VenueInvitationMailSkipped "recipient_snapshot_mismatch")
                else if jobVenueId /= Just invitation.venueId
                    then fail "Venue invitation envelope has invalid venue provenance"
                    else case invitationSkipReason now invitation of
                        Just reason -> pure (VenueInvitationMailSkipped reason)
                        Nothing -> do
                            venue <- fetch (Id invitation.venueId :: Id Venue)
                            pure $ VenueInvitationMailReady VenueInvitationMail
                                { invitation
                                , recipientAddress
                                , venue
                                , inviteUrl = venueInvitationUrl appBaseUrl invitation
                                , fromAddress = settings.mailFromAddress
                                , replyToAddress = settings.mailReplyToAddress
                                , supportEmail = settings.mailSupportEmail
                                }

loadVenueOnboardingInvitationMail ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Text ->
    UUID ->
    Maybe UUID ->
    AppMailSettings ->
    Text ->
    IO VenueOnboardingInvitationMailProjection
loadVenueOnboardingInvitationMail recipientIdentityId recipientAddress invitationId jobVenueId settings appBaseUrl = do
    maybeInvitation <- query @VenueOnboardingInvitation
        |> filterWhere (#id, Id invitationId)
        |> fetchOneOrNothing
    case maybeInvitation of
        Nothing -> pure (VenueOnboardingInvitationMailSkipped "domain_reference_missing")
        Just invitation -> do
            now <- getCurrentTime
            if recipientIdentityId /= invitationId || recipientAddress /= invitation.email
                then pure (VenueOnboardingInvitationMailSkipped "recipient_snapshot_mismatch")
                else if isJust jobVenueId
                    then fail "Venue onboarding invitation envelope must not have venue provenance"
                    else case onboardingInvitationSkipReason now invitation of
                        Just reason -> pure (VenueOnboardingInvitationMailSkipped reason)
                        Nothing -> pure $ VenueOnboardingInvitationMailReady VenueOnboardingInvitationMail
                            { invitation
                            , recipientAddress
                            , inviteUrl = venueOnboardingInvitationUrl appBaseUrl invitation
                            , fromAddress = settings.mailFromAddress
                            , replyToAddress = settings.mailReplyToAddress
                            , supportEmail = settings.mailSupportEmail
                            }

completeVenueInvitationEmail ::
    (?modelContext :: ModelContext) =>
    UUID ->
    IO VenueInvitation
completeVenueInvitationEmail invitationId = do
    invitation <- fetch (Id invitationId :: Id VenueInvitation)
    now <- getCurrentTime
    invitation
        |> set #deliveryStatus Sent
        |> set #deliveryError Nothing
        |> set #deliveredAt (Just now)
        |> updateRecord

completeVenueOnboardingInvitationEmail ::
    (?modelContext :: ModelContext) =>
    UUID ->
    IO VenueOnboardingInvitation
completeVenueOnboardingInvitationEmail invitationId = do
    invitation <- fetch (Id invitationId :: Id VenueOnboardingInvitation)
    now <- getCurrentTime
    invitation
        |> set #deliveryStatus Sent
        |> set #deliveryError Nothing
        |> set #deliveredAt (Just now)
        |> updateRecord

markInvitationDeliveryFailed ::
    (?modelContext :: ModelContext) =>
    Text ->
    UUID ->
    IO ()
markInvitationDeliveryFailed mailKind invitationId
    | mailKind == venueInvitationMailKind =
        void $ withVenueInvitationLockInCurrentTransaction invitationId do
            invitation <- fetch (Id invitationId :: Id VenueInvitation)
            now <- getCurrentTime
            when (isNothing (invitationSkipReason now invitation)) $
                void $
                    invitation
                        |> set #deliveryStatus InvitationDeliveryStatusEnumFailed
                        |> set #deliveryError (Just "Email delivery failed after ten attempts.")
                        |> updateRecord
    | mailKind == venueOnboardingInvitationMailKind =
        void $ withVenueOnboardingInvitationLock invitationId do
            invitation <- fetch (Id invitationId :: Id VenueOnboardingInvitation)
            now <- getCurrentTime
            when (isNothing (onboardingInvitationSkipReason now invitation)) $
                void $
                    invitation
                        |> set #deliveryStatus InvitationDeliveryStatusEnumFailed
                        |> set #deliveryError (Just "Email delivery failed after ten attempts.")
                        |> updateRecord
    | otherwise = pure ()

invitationSkipReason :: UTCTime -> VenueInvitation -> Maybe Text
invitationSkipReason now invitation
    | invitation.deliveryStatus == Sent = Just "already_delivered"
    | isJust invitation.acceptedAt || invitation.status == Accepted = Just "consumed"
    | invitation.status == Revoked = Just "revoked_or_replaced"
    | venueInvitationEffectiveExpiresAt invitation <= now = Just "expired"
    | not (venueInvitationIsActive now invitation) = Just "obsolete"
    | otherwise = Nothing

onboardingInvitationSkipReason :: UTCTime -> VenueOnboardingInvitation -> Maybe Text
onboardingInvitationSkipReason now invitation
    | invitation.deliveryStatus == Sent = Just "already_delivered"
    | isJust invitation.acceptedAt || invitation.status == Accepted = Just "consumed"
    | invitation.status == Revoked = Just "revoked_or_replaced"
    | maybe False (<= now) invitation.expiresAt = Just "expired"
    | not (venueOnboardingInvitationIsActive now invitation) = Just "obsolete"
    | otherwise = Nothing

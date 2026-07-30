{-# LANGUAGE RankNTypes #-}

module Application.VenueOnboardingInvitation.Mutations
    ( withVenueOnboardingInvitationLock
    , withVenueOnboardingInvitationRenewalLock
    ) where

import qualified Database.PostgreSQL.Simple as PG
import IHP.ControllerPrelude

-- IHP QueryBuilder does not expose row locks. Keep the unavoidable locking SQL
-- isolated here; callers perform all reads and writes through QueryBuilder while
-- this transaction serializes acceptance, renewal, and delivery for one invite.
withVenueOnboardingInvitationLock ::
    (?modelContext :: ModelContext) =>
    UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withVenueOnboardingInvitationLock invitationId action =
    withTransaction do
        lockVenueOnboardingInvitation invitationId action

withVenueOnboardingInvitationRenewalLock ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Text ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withVenueOnboardingInvitationRenewalLock invitationId correctedEmail action =
    withTransaction do
        emailLockResults :: [PG.Only Bool] <- sqlQuery
            "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS onboarding_email_lock"
            (PG.Only correctedEmail)
        unless (emailLockResults == [PG.Only True]) do
            error "Unable to lock onboarding invitation renewal email"
        lockVenueOnboardingInvitation invitationId action

lockVenueOnboardingInvitation ::
    (?modelContext :: ModelContext) =>
    UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
lockVenueOnboardingInvitation invitationId action = do
    lockedIds :: [PG.Only UUID] <- sqlQuery
        "SELECT id FROM venue_onboarding_invitations WHERE id = ? FOR UPDATE"
        (PG.Only invitationId)
    case lockedIds of
        [_] -> Just <$> action
        []  -> pure Nothing
        _   -> error "Onboarding invitation lock returned multiple rows"

{-# LANGUAGE RankNTypes #-}

module Application.VenueInvitation.Mutations
    ( withTrialStaffInvitationLockInCurrentTransaction
    , withVenueInvitationAcceptanceLockInCurrentTransaction
    , withVenueInvitationEmailLockInCurrentTransaction
    , withVenueInvitationLockInCurrentTransaction
    , withVenueInvitationRenewalLockInCurrentTransaction
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import qualified Data.Text as Text
import qualified Database.PostgreSQL.Simple as PG
import IHP.ControllerPrelude

withVenueInvitationLockInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withVenueInvitationLockInCurrentTransaction = lockVenueInvitation

withVenueInvitationAcceptanceLockInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Maybe UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withVenueInvitationAcceptanceLockInCurrentTransaction invitationId maybeStaffId action = do
    forM_ maybeStaffId lockTrialStaff
    lockVenueInvitation invitationId action

withVenueInvitationEmailLockInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    Text ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO result
withVenueInvitationEmailLockInCurrentTransaction email action = do
    lockVenueInvitationEmail email
    action

withVenueInvitationRenewalLockInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Maybe UUID ->
    Text ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withVenueInvitationRenewalLockInCurrentTransaction invitationId maybeStaffId correctedEmail action = do
    lockVenueInvitationEmail correctedEmail
    forM_ maybeStaffId lockTrialStaff
    lockVenueInvitation invitationId action

withTrialStaffInvitationLockInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Text ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withTrialStaffInvitationLockInCurrentTransaction staffId email action = do
    lockVenueInvitationEmail email
    lockedStaffIds :: [PG.Only UUID] <- sqlQuery
        "SELECT id FROM staff WHERE id = ? FOR UPDATE"
        (PG.Only staffId)
    case lockedStaffIds of
        [_] -> Just <$> action
        []  -> pure Nothing
        _   -> externalRuntimeInvariantFailure PersistedRuntimeInvariant "Trial staff lock returned multiple rows"

lockVenueInvitationEmail :: (?modelContext :: ModelContext) => Text -> IO ()
lockVenueInvitationEmail email = do
    lockResults :: [PG.Only Bool] <- sqlQuery
        "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS venue_invitation_email_lock"
        (PG.Only (Text.toCaseFold (Text.strip email)))
    unless (lockResults == [PG.Only True]) do
        externalRuntimeInvariantFailure PersistedRuntimeInvariant "Unable to lock venue invitation email"

lockTrialStaff :: (?modelContext :: ModelContext) => UUID -> IO ()
lockTrialStaff staffId = do
    lockedStaffIds :: [PG.Only UUID] <- sqlQuery
        "SELECT id FROM staff WHERE id = ? FOR UPDATE"
        (PG.Only staffId)
    unless (lockedStaffIds == [PG.Only staffId]) do
        externalRuntimeInvariantFailure PersistedRuntimeInvariant "Unable to lock trial staff"

lockVenueInvitation ::
    (?modelContext :: ModelContext) =>
    UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
lockVenueInvitation invitationId action = do
    lockedInvitationIds :: [PG.Only UUID] <- sqlQuery
        "SELECT id FROM venue_invitations WHERE id = ? FOR UPDATE"
        (PG.Only invitationId)
    case lockedInvitationIds of
        [_] -> Just <$> action
        []  -> pure Nothing
        _   -> externalRuntimeInvariantFailure PersistedRuntimeInvariant "Venue invitation lock returned multiple rows"

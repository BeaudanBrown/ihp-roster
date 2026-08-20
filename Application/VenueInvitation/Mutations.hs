{-# LANGUAGE RankNTypes #-}

module Application.VenueInvitation.Mutations
    ( withTrialStaffInvitationLockInCurrentTransaction
    , withVenueInvitationAcceptanceLockInCurrentTransaction
    , withVenueInvitationEmailLock
    , withVenueInvitationLock
    , withVenueInvitationRenewalLock
    , withVenueInvitationRenewalLockInCurrentTransaction
    ) where

import qualified Database.PostgreSQL.Simple as PG
import IHP.ControllerPrelude

withVenueInvitationLock ::
    (?modelContext :: ModelContext) =>
    UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withVenueInvitationLock invitationId action =
    withTransaction (lockVenueInvitation invitationId action)

withVenueInvitationAcceptanceLockInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Maybe UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withVenueInvitationAcceptanceLockInCurrentTransaction invitationId maybeStaffId action = do
    forM_ maybeStaffId lockTrialStaff
    lockVenueInvitation invitationId action

withVenueInvitationEmailLock ::
    (?modelContext :: ModelContext) =>
    Text ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO result
withVenueInvitationEmailLock email action =
    withTransaction do
        lockVenueInvitationEmail email
        action

-- Sequential compatibility wrapper retained for Admin producers until #390.
-- Atomic producers must use the current-transaction variant below.
withVenueInvitationRenewalLock ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Maybe UUID ->
    Text ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withVenueInvitationRenewalLock invitationId maybeStaffId correctedEmail action =
    withTransaction (withVenueInvitationRenewalLockInCurrentTransaction invitationId maybeStaffId correctedEmail action)

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
        _   -> error "Trial staff lock returned multiple rows"

lockVenueInvitationEmail :: (?modelContext :: ModelContext) => Text -> IO ()
lockVenueInvitationEmail email = do
    lockResults :: [PG.Only Bool] <- sqlQuery
        "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS venue_invitation_email_lock"
        (PG.Only email)
    unless (lockResults == [PG.Only True]) do
        error "Unable to lock venue invitation email"

lockTrialStaff :: (?modelContext :: ModelContext) => UUID -> IO ()
lockTrialStaff staffId = do
    lockedStaffIds :: [PG.Only UUID] <- sqlQuery
        "SELECT id FROM staff WHERE id = ? FOR UPDATE"
        (PG.Only staffId)
    unless (lockedStaffIds == [PG.Only staffId]) do
        error "Unable to lock trial staff"

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
        _   -> error "Venue invitation lock returned multiple rows"

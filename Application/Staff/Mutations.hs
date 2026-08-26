module Application.Staff.Mutations
    ( withStaffOperationalLocksInCurrentTransaction
    , withStaffRemovalLockInCurrentTransaction
    ) where

import qualified Data.List as List
import qualified Data.UUID as UUID
import qualified Database.PostgreSQL.Simple as PG
import IHP.ControllerPrelude

withStaffOperationalLocksInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    [UUID] ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withStaffOperationalLocksInCurrentTransaction staffIds action = do
    let orderedStaffIds = List.sort (List.nub staffIds)
    mapM_ lockStaffOperationalKey orderedStaffIds
    matchingStaffIds <- mapM fetchMatchingStaffId orderedStaffIds
    if matchingStaffIds == map Just orderedStaffIds
        then Just <$> action
        else pure Nothing

withStaffRemovalLockInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withStaffRemovalLockInCurrentTransaction staffId action = do
        lockStaffOperationalKey staffId
        lockedStaffIds :: [PG.Only UUID] <- sqlQuery
            "SELECT id FROM staff WHERE id = ? FOR UPDATE"
            (PG.Only staffId)
        case lockedStaffIds of
            [PG.Only lockedStaffId]
                | lockedStaffId == staffId -> Just <$> action
            [] -> pure Nothing
            _ -> error "Staff removal lock returned an unexpected row set"

fetchMatchingStaffId :: (?modelContext :: ModelContext) => UUID -> IO (Maybe UUID)
fetchMatchingStaffId staffId = do
    matchingStaffIds :: [PG.Only UUID] <- sqlQuery
        "SELECT id FROM staff WHERE id = ?"
        (PG.Only staffId)
    case matchingStaffIds of
        [PG.Only matchingStaffId]
            | matchingStaffId == staffId -> pure (Just matchingStaffId)
        [] -> pure Nothing
        _ -> error "Staff operational lock returned an unexpected row set"

lockStaffOperationalKey :: (?modelContext :: ModelContext) => UUID -> IO ()
lockStaffOperationalKey staffId = do
    let lockKey = "staff-operational:" <> UUID.toText staffId
    lockResults :: [PG.Only Bool] <- sqlQuery
        "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS staff_operational_lock"
        (PG.Only lockKey)
    unless (lockResults == [PG.Only True]) do
        error "Unable to lock staff operational key"

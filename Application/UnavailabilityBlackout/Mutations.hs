module Application.UnavailabilityBlackout.Mutations
    ( blackoutOverlapError
    , createUnavailabilityBlackout
    , deleteUnavailabilityBlackout
    , findOverlappingUnavailabilityBlackout
    , lockVenueUnavailabilityBlackoutInCurrentTransaction
    , updateUnavailabilityBlackout
    , withVenueUnavailabilityBlackoutLock
    ) where

import qualified Data.UUID as UUID
import qualified Database.PostgreSQL.Simple as PG
import Generated.Types hiding (createUnavailabilityBlackout)
import IHP.ControllerPrelude

blackoutOverlapError :: Text
blackoutOverlapError = "Blackout periods cannot overlap an existing active period."

withVenueUnavailabilityBlackoutLock ::
    (?modelContext :: ModelContext) =>
    UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO result
withVenueUnavailabilityBlackoutLock venueId action =
    withTransaction do
        lockVenueUnavailabilityBlackoutInCurrentTransaction venueId
        action

lockVenueUnavailabilityBlackoutInCurrentTransaction :: (?modelContext :: ModelContext) => UUID -> IO ()
lockVenueUnavailabilityBlackoutInCurrentTransaction venueId = do
    let lockKey = "unavailability-blackout:" <> UUID.toText venueId
    lockResults :: [PG.Only Bool] <- sqlQuery
        "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS unavailability_blackout_lock"
        (PG.Only lockKey)
    unless (lockResults == [PG.Only True]) do
        error "Unable to lock unavailability blackout key"

findOverlappingUnavailabilityBlackout ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Day ->
    Day ->
    Maybe (Id UnavailabilityBlackout) ->
    IO (Maybe UnavailabilityBlackout)
findOverlappingUnavailabilityBlackout venueId firstDate lastDate excludedId =
    case excludedId of
        Nothing -> baseQuery |> fetchOneOrNothing
        Just blackoutId -> baseQuery |> filterWhereNot (#id, blackoutId) |> fetchOneOrNothing
  where
    baseQuery =
        query @UnavailabilityBlackout
            |> filterWhere (#venueId, venueId)
            |> filterWhereLessThanOrEqualTo (#startDate, lastDate)
            |> filterWhereGreaterThanOrEqualTo (#endDate, firstDate)
            |> orderByAsc #startDate
            |> orderByAsc #id

createUnavailabilityBlackout ::
    (?modelContext :: ModelContext) =>
    UnavailabilityBlackout ->
    IO (Either Text UnavailabilityBlackout)
createUnavailabilityBlackout blackout =
    withVenueUnavailabilityBlackoutLock blackout.venueId do
        findOverlappingUnavailabilityBlackout blackout.venueId blackout.startDate blackout.endDate Nothing >>= \case
            Just _ -> pure (Left blackoutOverlapError)
            Nothing -> Right <$> createRecord blackout

updateUnavailabilityBlackout ::
    (?modelContext :: ModelContext) =>
    UnavailabilityBlackout ->
    IO (Either Text UnavailabilityBlackout)
updateUnavailabilityBlackout submitted =
    withVenueUnavailabilityBlackoutLock submitted.venueId do
        lockedIds :: [PG.Only UUID] <- sqlQuery
            "SELECT id FROM unavailability_blackouts WHERE id = ? AND venue_id = ? FOR UPDATE"
            (unpackId submitted.id, submitted.venueId)
        case lockedIds of
            [] -> pure (Left "This blackout period no longer exists.")
            [PG.Only _] ->
                findOverlappingUnavailabilityBlackout submitted.venueId submitted.startDate submitted.endDate (Just submitted.id) >>= \case
                    Just _ -> pure (Left blackoutOverlapError)
                    Nothing -> do
                        now <- getCurrentTime
                        Right <$> (submitted |> set #updatedAt now |> updateRecord)
            _ -> error "Blackout update lock returned an unexpected row set"

deleteUnavailabilityBlackout ::
    (?modelContext :: ModelContext) =>
    UnavailabilityBlackout ->
    IO Bool
deleteUnavailabilityBlackout blackout =
    withVenueUnavailabilityBlackoutLock blackout.venueId do
        lockedIds :: [PG.Only UUID] <- sqlQuery
            "SELECT id FROM unavailability_blackouts WHERE id = ? AND venue_id = ? FOR UPDATE"
            (unpackId blackout.id, blackout.venueId)
        case lockedIds of
            [] -> pure False
            [PG.Only _] -> do
                deleteRecord blackout
                pure True
            _ -> error "Blackout delete lock returned an unexpected row set"

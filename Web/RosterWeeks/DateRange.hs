module Web.RosterWeeks.DateRange
    ( RosterDayRowRemovalPreview (..)
    , RosterWindow (..)
    , RosterWindowDay (..)
    , RosterWindowLane (..)
    , appendRosterWindowLane
    , laneForOperationalDate
    , materializeRosterWindow
    , previewRemoveRosterDayRowByLanes
    , removeRosterDayRowByLanes
    , removeRosterWindowLane
    , repackRosterWindow
    , resolveRosterLaneReference
    , projectRosterWindow
    , projectedRosterDay
    , projectedRosterDayId
    , rosterPlanningWeekForDay
    , rosterWindowDates
    , rosterWindowIsPublished
    , rosterWindowLaneRepresentative
    , fetchRosterWindow
    ) where

import Application.Helper.WeekBoundaries (venueWeekOffsetForDay,
                                          venueWeekStartDate)
import Application.RosterPublication (rosterDaysArePublished)
import Control.Monad (void)
import qualified "crypton" Crypto.Hash as Hash
import Data.List (foldl', sortOn)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import Generated.Types
import Web.Controller.Prelude

-- | Seven explicit Operational dates and their sparse persisted roster facts.
-- Missing days remain projections; mutation code decides when to materialize.
data RosterDayRowRemovalPreview = RosterDayRowRemovalPreview
    { laneRowRemovalOverflowCount    :: !Int
    , laneRowRemovalDeletedDataCount :: !Int
    }
    deriving (Eq, Show)

data RosterWindow = RosterWindow
    { rosterWindowStartDate     :: !Day
    , rosterWindowProjectedDays :: ![RosterWindowDay]
    , rosterWindowLanes         :: ![RosterWindowLane]
    }
    deriving (Eq, Show)

data RosterWindowDay = RosterWindowDay
    { operationalDate    :: !Day
    , persistedRosterDay :: !(Maybe RosterDay)
    }
    deriving (Eq, Show)

-- | One display lane in the normalized union. Identity remains date-local;
-- callers must resolve the lane for the target Operational date before writing.
data RosterWindowLane = RosterWindowLane
    { rosterWindowLaneName           :: !Text
    , rosterWindowLaneNormalizedName :: !Text
    , rosterWindowLaneFirstSeen      :: !(Int, Int, UUID)
    , rosterWindowLaneByDate         :: !(Map.Map Day RosterLane)
    }
    deriving (Eq, Show)

rosterWindowDates :: Day -> [Day]
rosterWindowDates startDate = map (`addDays` startDate) [0 .. 6]

rosterWindowIsPublished :: RosterWindow -> Bool
rosterWindowIsPublished window =
    rosterDaysArePublished (mapMaybe (.persistedRosterDay) window.rosterWindowProjectedDays)

projectRosterWindow :: Day -> [RosterDay] -> [RosterLane] -> RosterWindow
projectRosterWindow startDate persistedDays persistedLanes =
    RosterWindow
        { rosterWindowStartDate = startDate
        , rosterWindowProjectedDays = projectedDays
        , rosterWindowLanes = sortOn rosterWindowLaneFirstSeen (Map.elems laneUnion)
        }
  where
    dates = rosterWindowDates startDate
    dayByDate = Map.fromList [(day.operationalDate, day) | day <- persistedDays, day.operationalDate `elem` dates]
    projectedDays = [RosterWindowDay date (Map.lookup date dayByDate) | date <- dates]
    dateByDayId = Map.fromList [(unpackId day.id, day.operationalDate) | day <- persistedDays]
    lanesByDate = Map.fromListWith (<>)
        [ (date, [lane])
        | lane <- persistedLanes
        , isNothing lane.deletedAt
        , Just date <- [Map.lookup lane.rosterDayId dateByDayId]
        , date `elem` dates
        ]
    orderedLanes =
        [ (dayIndex, laneIndex, date, lane)
        | (dayIndex, date) <- zip [0 ..] dates
        , (laneIndex, lane) <- zip [0 ..] (sortOn laneOrder (Map.findWithDefault [] date lanesByDate))
        ]
    laneUnion = foldl' addLane Map.empty orderedLanes
    laneOrder lane = (lane.sortOrder, lane.createdAt, lane.id)
    addLane union (dayIndex, laneIndex, date, lane) =
        Map.insertWith mergeLane normalized candidate union
      where
        normalized = normalizeLaneName lane.name
        candidate = RosterWindowLane
            { rosterWindowLaneName = Text.strip lane.name
            , rosterWindowLaneNormalizedName = normalized
            , rosterWindowLaneFirstSeen = (dayIndex, laneIndex, unpackId lane.id)
            , rosterWindowLaneByDate = Map.singleton date lane
            }
        mergeLane _new existing =
            existing
                { rosterWindowLaneByDate = Map.insertWith (\_ old -> old) date lane existing.rosterWindowLaneByDate
                }

laneForOperationalDate :: Day -> RosterWindowLane -> Maybe RosterLane
laneForOperationalDate date lane = Map.lookup date lane.rosterWindowLaneByDate

rosterWindowLaneRepresentative :: RosterWindowLane -> RosterLane
rosterWindowLaneRepresentative lane =
    snd (fromMaybe (error "Roster window lane has no date-local lane") (Map.lookupMin lane.rosterWindowLaneByDate))

projectedRosterDay :: Id Venue -> Id RosterGroup -> Maybe (Id RosterWeek) -> Day -> RosterWindowDay -> RosterDay
projectedRosterDay venueId rosterGroupId maybeRosterWeekId windowStartDate windowDay =
    case windowDay.persistedRosterDay of
        Just rosterDay -> rosterDay
        Nothing ->
            newRecord @RosterDay
                |> set #id (projectedRosterDayId rosterGroupId windowDay.operationalDate)
                |> set #rosterWeekId (unpackId <$> maybeRosterWeekId)
                |> set #venueId (unpackId venueId)
                |> set #rosterGroupId (unpackId rosterGroupId)
                |> set #operationalDate windowDay.operationalDate
                |> set #publicationState Draft
                |> set #dayOffset (fromInteger (diffDays windowDay.operationalDate windowStartDate))

rosterPlanningWeekForDay :: (?modelContext :: ModelContext) => RosterDay -> IO RosterWeek
rosterPlanningWeekForDay rosterDay = do
    venueConfig <- query @VenueConfig
        |> filterWhere (#venueId, rosterDay.venueId)
        |> fetchOne
    let weekOffset = venueWeekOffsetForDay venueConfig rosterDay.operationalDate
        windowStartDate = venueWeekStartDate venueConfig weekOffset
    window <- fetchRosterWindow (Id rosterDay.venueId) (Id rosterDay.rosterGroupId) windowStartDate
    let published = rosterWindowIsPublished window
    case rosterDay.rosterWeekId of
        Just rosterWeekId -> do
            legacyWeek <- fetch (Id rosterWeekId :: Id RosterWeek)
            pure (legacyWeek |> set #isLive published)
        Nothing ->
            pure $
                newRecord @RosterWeek
                    |> set #venueId rosterDay.venueId
                    |> set #rosterGroupId rosterDay.rosterGroupId
                    |> set #weekOffset weekOffset
                    |> set #isLive published

projectedRosterDayId :: Id RosterGroup -> Day -> Id RosterDay
projectedRosterDayId rosterGroupId operationalDate =
    Id (fromMaybe (error "MD5 roster-day projection did not produce a UUID") (UUID.fromText uuidText))
  where
    digest :: Hash.Digest Hash.MD5
    digest = Hash.hash (TextEncoding.encodeUtf8 (tshow rosterGroupId <> ":" <> tshow operationalDate))
    hex = cs (show digest) :: Text
    uuidText = Text.intercalate "-"
        [ Text.take 8 hex
        , Text.take 4 (Text.drop 8 hex)
        , Text.take 4 (Text.drop 12 hex)
        , Text.take 4 (Text.drop 16 hex)
        , Text.take 12 (Text.drop 20 hex)
        ]

fetchRosterWindow :: (?modelContext :: ModelContext) => Id Venue -> Id RosterGroup -> Day -> IO RosterWindow
fetchRosterWindow venueId rosterGroupId startDate = do
    let endDate = addDays 6 startDate
    days <- query @RosterDay
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> filterWhereGreaterThanOrEqualTo (#operationalDate, startDate)
        |> filterWhereLessThanOrEqualTo (#operationalDate, endDate)
        |> fetch
    lanes <- if null days
        then pure []
        else query @RosterLane
            |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) days)
            |> filterWhere (#deletedAt, Nothing)
            |> fetch
    let persistedWindow = projectRosterWindow startDate days lanes
    if not (null persistedWindow.rosterWindowLanes)
        then pure persistedWindow
            { rosterWindowLanes = map (projectMissingLaneDates (rosterWindowDates startDate)) persistedWindow.rosterWindowLanes
            }
        else do
            configuredNames <- query @SlotName
                |> filterWhere (#venueId, unpackId venueId)
                |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
                |> filterWhere (#isActive, True)
                |> orderByAsc #sortOrder
                |> orderByAsc #createdAt
                |> fetch
            let dates = rosterWindowDates startDate
                projectedWindowLanes =
                    [ RosterWindowLane
                        { rosterWindowLaneName = slotName.name
                        , rosterWindowLaneNormalizedName = normalizeLaneName slotName.name
                        , rosterWindowLaneFirstSeen = (0, slotName.sortOrder, unpackId (projectedRosterLaneId (projectedRosterDayId rosterGroupId startDate) slotName.name))
                        , rosterWindowLaneByDate = Map.fromList
                            [ (operationalDate, projectedLane operationalDate slotName)
                            | operationalDate <- dates
                            ]
                        }
                    | slotName <- configuredNames
                    ]
                projectedLane operationalDate slotName =
                    let rosterDayId = projectedRosterDayId rosterGroupId operationalDate
                     in newRecord @RosterLane
                            |> set #id (projectedRosterLaneId rosterDayId slotName.name)
                            |> set #rosterDayId (unpackId rosterDayId)
                            |> set #legacyRosterWeekSlotDefinitionId Nothing
                            |> set #name slotName.name
                            |> set #sortOrder slotName.sortOrder
            pure persistedWindow { rosterWindowLanes = projectedWindowLanes }
  where
    projectMissingLaneDates dates windowLane =
        windowLane
            { rosterWindowLaneByDate = foldl' addProjectedLane windowLane.rosterWindowLaneByDate dates
            }
      where
        addProjectedLane lanesByDate operationalDate =
            Map.insertWith (\_ persistedLane -> persistedLane) operationalDate (projectedLane operationalDate) lanesByDate
        projectedLane operationalDate =
            let rosterDayId = projectedRosterDayId rosterGroupId operationalDate
                sortOrder = let (_, laneSortOrder, _) = windowLane.rosterWindowLaneFirstSeen in laneSortOrder
             in newRecord @RosterLane
                    |> set #id (projectedRosterLaneId rosterDayId windowLane.rosterWindowLaneName)
                    |> set #rosterDayId (unpackId rosterDayId)
                    |> set #legacyRosterWeekSlotDefinitionId Nothing
                    |> set #name windowLane.rosterWindowLaneName
                    |> set #sortOrder sortOrder

-- | Materialize sparse Draft days and their date-local lane sets only at the
-- mutation seam. Existing rough lane unions are copied by normalized name;
-- brand-new windows start from the roster group's configured slot names.
materializeRosterWindow :: (?modelContext :: ModelContext) => Id Venue -> Id RosterGroup -> Int -> IO ([RosterDay], Bool)
materializeRosterWindow venueId rosterGroupId weekOffset = do
    venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venueId) |> fetchOne
    let startDate = venueWeekStartDate venueConfig weekOffset
    window <- fetchRosterWindow venueId rosterGroupId startDate
    when (any (maybe False ((/= Draft) . (.publicationState)) . (.persistedRosterDay)) window.rosterWindowProjectedDays) $
        error "Published roster days cannot be materialized as a Draft planning window"
    materializedDays <- forM (zip [0 :: Int ..] window.rosterWindowProjectedDays) \(dayOffset, windowDay) ->
        case windowDay.persistedRosterDay of
            Just day -> pure day
            Nothing ->
                projectedRosterDay venueId rosterGroupId Nothing startDate windowDay
                    |> set #dayOffset dayOffset
                    |> createRecord
    configuredNames <- query @SlotName
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> filterWhere (#isActive, True)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch
    let unionTemplates =
            if null window.rosterWindowLanes
                then [(slotName.name, slotName.sortOrder) | slotName <- configuredNames]
                else [(lane.rosterWindowLaneName, sortOrder) | (sortOrder, lane) <- zip [0 ..] window.rosterWindowLanes]
    forM_ materializedDays \day -> do
        existing <- query @RosterLane
            |> filterWhere (#rosterDayId, unpackId day.id)
            |> fetch
        let activeNames = map (normalizeLaneName . (.name)) (filter (isNothing . (.deletedAt)) existing)
        forM_ unionTemplates \(name, sortOrder) ->
            unless (normalizeLaneName name `elem` activeNames) do
                case find ((== normalizeLaneName name) . normalizeLaneName . (.name)) existing of
                    Just retainedLane ->
                        void $
                            retainedLane
                                |> set #name (Text.strip name)
                                |> set #sortOrder sortOrder
                                |> set #deletedAt Nothing
                                |> set #deletedByUserId Nothing
                                |> set #deleteReason Nothing
                                |> updateRecord
                    Nothing ->
                        void $
                            newRecord @RosterLane
                                |> set #id (projectedRosterLaneId day.id name)
                                |> set #rosterDayId (unpackId day.id)
                                |> set #legacyRosterWeekSlotDefinitionId Nothing
                                |> set #name (Text.strip name)
                                |> set #sortOrder sortOrder
                                |> createRecord
    pure (materializedDays, any (isNothing . (.persistedRosterDay)) window.rosterWindowProjectedDays)

-- | Resolve current date-local lane IDs, with a bounded compatibility fallback
-- for callers still carrying a legacy weekly definition UUID.
resolveRosterLaneReference :: (?modelContext :: ModelContext) => Maybe (Id RosterDay) -> Id RosterLane -> IO (Maybe RosterLane)
resolveRosterLaneReference maybeRosterDayId requestedId = do
    direct <- query @RosterLane
        |> filterWhere (#id, requestedId)
        |> filterWhere (#deletedAt, Nothing)
        |> maybeFilterDay
        |> fetchOneOrNothing
    case direct of
        Just lane -> pure (Just lane)
        Nothing -> query @RosterLane
            |> filterWhere (#legacyRosterWeekSlotDefinitionId, Just (unpackId requestedId))
            |> filterWhere (#deletedAt, Nothing)
            |> maybeFilterDay
            |> orderByAsc #createdAt
            |> fetchOneOrNothing
  where
    maybeFilterDay queryBuilder = case maybeRosterDayId of
        Nothing -> queryBuilder
        Just rosterDayId -> queryBuilder |> filterWhere (#rosterDayId, unpackId rosterDayId)

appendRosterWindowLane :: (?modelContext :: ModelContext) => Id Venue -> Id RosterGroup -> Int -> Text -> IO (Either Text RosterLane)
appendRosterWindowLane venueId rosterGroupId weekOffset requestedName = do
    venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venueId) |> fetchOne
    let startDate = venueWeekStartDate venueConfig weekOffset
        normalized = normalizeLaneName requestedName
    if Text.null normalized
        then pure (Left "Roster column names cannot be blank.")
        else do
            (days, _) <- materializeRosterWindow venueId rosterGroupId weekOffset
            window <- fetchRosterWindow venueId rosterGroupId startDate
            if normalized `elem` map (.rosterWindowLaneNormalizedName) window.rosterWindowLanes
                then pure (Left "A column with that name already exists for this window.")
                else do
                    let nextSortOrder = length window.rosterWindowLanes
                    created <- forM days \day -> do
                        retained <- query @RosterLane
                            |> filterWhere (#rosterDayId, unpackId day.id)
                            |> fetch
                            |> fmap (find ((== normalized) . normalizeLaneName . (.name)))
                        case retained of
                            Just retainedLane ->
                                retainedLane
                                    |> set #name (Text.strip requestedName)
                                    |> set #sortOrder nextSortOrder
                                    |> set #deletedAt Nothing
                                    |> set #deletedByUserId Nothing
                                    |> set #deleteReason Nothing
                                    |> updateRecord
                            Nothing ->
                                newRecord @RosterLane
                                    |> set #id (projectedRosterLaneId day.id requestedName)
                                    |> set #rosterDayId (unpackId day.id)
                                    |> set #legacyRosterWeekSlotDefinitionId Nothing
                                    |> set #name (Text.strip requestedName)
                                    |> set #sortOrder nextSortOrder
                                    |> createRecord
                    pure (maybe (Left "Roster window has no days.") Right (listToMaybe created))

removeRosterWindowLane :: (?modelContext :: ModelContext) => Id Venue -> Id RosterGroup -> Int -> Id RosterLane -> Id User -> IO (Either Text ())
removeRosterWindowLane venueId rosterGroupId weekOffset requestedLaneId deletedByUserId = do
    requestedLane <- fetch requestedLaneId
    requestedDay <- fetch (Id requestedLane.rosterDayId :: Id RosterDay)
    if requestedDay.venueId /= unpackId venueId || requestedDay.rosterGroupId /= unpackId rosterGroupId
        then pure (Left "Roster column is outside the selected venue or group.")
        else do
            _ <- materializeRosterWindow venueId rosterGroupId weekOffset
            venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venueId) |> fetchOne
            let startDate = venueWeekStartDate venueConfig weekOffset
            window <- fetchRosterWindow venueId rosterGroupId startDate
            if length window.rosterWindowLanes <= 1
                then pure (Left "Roster windows need at least one column.")
                else case find (\lane -> lane.rosterWindowLaneNormalizedName == normalizeLaneName requestedLane.name) window.rosterWindowLanes of
                    Nothing -> pure (Left "Roster column is not active in this window.")
                    Just removedWindowLane -> do
                        now <- getCurrentTime
                        forM_ window.rosterWindowProjectedDays \windowDay ->
                            forM_ windowDay.persistedRosterDay \day -> do
                                dayLanes <- query @RosterLane
                                    |> filterWhere (#rosterDayId, unpackId day.id)
                                    |> filterWhere (#deletedAt, Nothing)
                                    |> orderByAsc #sortOrder
                                    |> orderByAsc #createdAt
                                    |> fetch
                                let removedLanes = filter ((== removedWindowLane.rosterWindowLaneNormalizedName) . normalizeLaneName . (.name)) dayLanes
                                    remainingLanes = filter ((/= removedWindowLane.rosterWindowLaneNormalizedName) . normalizeLaneName . (.name)) dayLanes
                                unless (null removedLanes || null remainingLanes) do
                                    slots <- query @RosterSlot
                                        |> filterWhere (#rosterDayId, unpackId day.id)
                                        |> filterWhere (#deletedAt, Nothing)
                                        |> fetch
                                    let removedLaneIds = map (unpackId . (.id)) removedLanes
                                        movingSlots = sortOn (\slot -> (slot.rowIndex, slot.slotSortOrder, slot.createdAt, slot.id)) (filter (\slot -> slot.rosterLaneId `elem` removedLaneIds) slots)
                                        stationary = filter (\slot -> slot.rosterLaneId `notElem` removedLaneIds) slots
                                        occupiedStart = Set.fromList [(slot.rosterLaneId, slot.rowIndex) | slot <- stationary]
                                        candidates = [(lane, rowIndex) | rowIndex <- [0 ..], lane <- remainingLanes]
                                        placements = allocateLanePlacements occupiedStart candidates movingSlots
                                        temporaryBase = day.rowCount + 1000
                                    forM_ (zip [0 :: Int ..] movingSlots) \(index, slot) ->
                                        void (slot |> set #rowIndex (temporaryBase + index) |> updateRecord)
                                    forM_ placements \(slot, lane, rowIndex) ->
                                        void $
                                            slot
                                                |> set #rosterLaneId (unpackId lane.id)
                                                |> set #rosterWeekSlotDefinitionId lane.legacyRosterWeekSlotDefinitionId
                                                |> set #slotSortOrder lane.sortOrder
                                                |> set #rowIndex rowIndex
                                                |> updateRecord
                                    let requiredRows = 1 + maximum (0 : [rowIndex | (_, _, rowIndex) <- placements])
                                    when (requiredRows > day.rowCount) $
                                        void (day |> set #rowCount requiredRows |> updateRecord)
                                    forM_ removedLanes \lane ->
                                        void $
                                            lane
                                                |> set #deletedAt (Just now)
                                                |> set #deletedByUserId (Just (unpackId deletedByUserId))
                                                |> set #deleteReason (Just "roster_window_lane_removed")
                                                |> updateRecord
                        repackRosterWindow venueId rosterGroupId weekOffset
                        -- Legacy slot compatibility projection may reactivate a
                        -- lane while slots are repacked. Tombstone the removed
                        -- date-local identity last, after all slot writes.
                        forM_ window.rosterWindowProjectedDays \windowDay ->
                            forM_ windowDay.persistedRosterDay \day -> do
                                removedLanes <- query @RosterLane
                                    |> filterWhere (#rosterDayId, unpackId day.id)
                                    |> fetch
                                forM_ (filter ((== removedWindowLane.rosterWindowLaneNormalizedName) . normalizeLaneName . (.name)) removedLanes) \lane ->
                                    void $
                                        lane
                                            |> set #deletedAt (Just now)
                                            |> set #deletedByUserId (Just (unpackId deletedByUserId))
                                            |> set #deleteReason (Just "roster_window_lane_removed")
                                            |> updateRecord
                        pure (Right ())

data LaneRowRemovalPlan = LaneRowRemovalPlan
    { laneRowRemovalPlacements    :: ![(RosterSlot, RosterLane, Int)]
    , laneRowRemovalOverflowSlots :: ![RosterSlot]
    }

previewRemoveRosterDayRowByLanes :: (?modelContext :: ModelContext) => RosterDay -> IO RosterDayRowRemovalPreview
previewRemoveRosterDayRowByLanes rosterDay = do
    plan <- buildLaneRowRemovalPlan rosterDay
    pure RosterDayRowRemovalPreview
        { laneRowRemovalOverflowCount = length plan.laneRowRemovalOverflowSlots
        , laneRowRemovalDeletedDataCount = length plan.laneRowRemovalOverflowSlots
        }

removeRosterDayRowByLanes :: (?modelContext :: ModelContext) => RosterDay -> Id User -> IO ()
removeRosterDayRowByLanes rosterDay actorUserId = do
    plan <- buildLaneRowRemovalPlan rosterDay
    now <- getCurrentTime
    let movingSlots = map (\(slot, _, _) -> slot) plan.laneRowRemovalPlacements <> plan.laneRowRemovalOverflowSlots
        temporaryBase = rosterDay.rowCount + 1000
    forM_ (zip [0 :: Int ..] movingSlots) \(index, slot) ->
        void (slot |> set #rowIndex (temporaryBase + index) |> updateRecord)
    forM_ plan.laneRowRemovalPlacements \(slot, lane, rowIndex) ->
        void $
            slot
                |> set #rosterLaneId (unpackId lane.id)
                |> set #rosterWeekSlotDefinitionId lane.legacyRosterWeekSlotDefinitionId
                |> set #slotSortOrder lane.sortOrder
                |> set #rowIndex rowIndex
                |> updateRecord
    forM_ plan.laneRowRemovalOverflowSlots \slot ->
        void $
            slot
                |> set #deletedAt (Just now)
                |> set #deletedByUserId (Just (unpackId actorUserId))
                |> set #deleteReason (Just "roster_day_row_removed")
                |> updateRecord
    void (rosterDay |> set #rowCount (max 2 (rosterDay.rowCount - 1)) |> updateRecord)

buildLaneRowRemovalPlan :: (?modelContext :: ModelContext) => RosterDay -> IO LaneRowRemovalPlan
buildLaneRowRemovalPlan rosterDay = do
    lanes <- query @RosterLane
        |> filterWhere (#rosterDayId, unpackId rosterDay.id)
        |> filterWhere (#deletedAt, Nothing)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch
    slots <- query @RosterSlot
        |> filterWhere (#rosterDayId, unpackId rosterDay.id)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    let lastRowIndex = max 0 (rosterDay.rowCount - 1)
        laneSortById = Map.fromList [(unpackId lane.id, lane.sortOrder) | lane <- lanes]
        movingSlots = sortOn (\slot -> (slot.rowIndex, Map.findWithDefault slot.slotSortOrder slot.rosterLaneId laneSortById, slot.startsAt, slot.createdAt, slot.id)) slots
        candidates =
            [ (lane, rowIndex)
            | rowIndex <- [0 .. lastRowIndex - 1]
            , lane <- lanes
            ]
        (placements, overflow) = allocateBoundedLanePlacements candidates movingSlots
    pure LaneRowRemovalPlan
        { laneRowRemovalPlacements = placements
        , laneRowRemovalOverflowSlots = overflow
        }

allocateBoundedLanePlacements :: [(RosterLane, Int)] -> [RosterSlot] -> ([(RosterSlot, RosterLane, Int)], [RosterSlot])
allocateBoundedLanePlacements _ [] = ([], [])
allocateBoundedLanePlacements [] slots = ([], slots)
allocateBoundedLanePlacements ((lane, rowIndex) : candidates) (slot : slots) =
    let (placements, overflow) = allocateBoundedLanePlacements candidates slots
     in ((slot, lane, rowIndex) : placements, overflow)

repackRosterWindow :: (?modelContext :: ModelContext) => Id Venue -> Id RosterGroup -> Int -> IO ()
repackRosterWindow venueId rosterGroupId weekOffset = do
    venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venueId) |> fetchOne
    window <- fetchRosterWindow venueId rosterGroupId (venueWeekStartDate venueConfig weekOffset)
    forM_ window.rosterWindowProjectedDays \windowDay ->
        forM_ windowDay.persistedRosterDay \day -> do
            lanes <- query @RosterLane
                |> filterWhere (#rosterDayId, unpackId day.id)
                |> filterWhere (#deletedAt, Nothing)
                |> orderByAsc #sortOrder
                |> orderByAsc #createdAt
                |> fetch
            unless (null lanes) do
                slots <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId day.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                staffMembers <- query @Staff
                    |> filterWhereIn (#id, [Id staffId | staffId <- nub (mapMaybe (.staffId) slots)])
                    |> fetch
                let staffById = Map.fromList [(unpackId staff.id, staff) | staff <- staffMembers]
                    staffSortKey slot = case slot.staffId >>= (`Map.lookup` staffById) of
                        Nothing -> (True, "", "", UUID.nil)
                        Just staff -> (False, Text.toCaseFold staff.lastName, Text.toCaseFold staff.firstName, unpackId staff.id)
                    orderedSlots = sortOn (\slot -> (staffSortKey slot, slot.rowIndex, slot.slotSortOrder, slot.createdAt, slot.id)) slots
                    rowsPerLane = max 2 ((length orderedSlots + length lanes - 1) `div` length lanes)
                    candidates = [(lane, rowIndex) | lane <- lanes, rowIndex <- [0 .. rowsPerLane - 1]]
                    placements = allocateLanePlacements Set.empty candidates orderedSlots
                    temporaryBase = day.rowCount + 1000
                forM_ (zip [0 :: Int ..] orderedSlots) \(index, slot) ->
                    void (slot |> set #rowIndex (temporaryBase + index) |> updateRecord)
                forM_ placements \(slot, lane, rowIndex) ->
                    void $
                        slot
                            |> set #rosterLaneId (unpackId lane.id)
                            |> set #rosterWeekSlotDefinitionId lane.legacyRosterWeekSlotDefinitionId
                            |> set #slotSortOrder lane.sortOrder
                            |> set #rowIndex rowIndex
                            |> updateRecord
                let requiredRows = rowsPerLane
                when (requiredRows /= day.rowCount) $
                    void (day |> set #rowCount requiredRows |> updateRecord)

allocateLanePlacements :: Set.Set (UUID, Int) -> [(RosterLane, Int)] -> [RosterSlot] -> [(RosterSlot, RosterLane, Int)]
allocateLanePlacements _ _ [] = []
allocateLanePlacements occupied candidates (slot : remainingSlots) =
    case find (\(lane, rowIndex) -> (unpackId lane.id, rowIndex) `Set.notMember` occupied) candidates of
        Nothing -> error "Infinite roster lane placement candidates were exhausted"
        Just (lane, rowIndex) ->
            (slot, lane, rowIndex)
                : allocateLanePlacements (Set.insert (unpackId lane.id, rowIndex) occupied) candidates remainingSlots

projectedRosterLaneId :: Id RosterDay -> Text -> Id RosterLane
projectedRosterLaneId rosterDayId name =
    Id (fromMaybe (error "MD5 roster-lane projection did not produce a UUID") (UUID.fromText uuidText))
  where
    digest :: Hash.Digest Hash.MD5
    digest = Hash.hash (TextEncoding.encodeUtf8 (tshow rosterDayId <> ":lane:" <> normalizeLaneName name))
    hex = cs (show digest) :: Text
    uuidText = Text.intercalate "-"
        [ Text.take 8 hex
        , Text.take 4 (Text.drop 8 hex)
        , Text.take 4 (Text.drop 12 hex)
        , Text.take 4 (Text.drop 16 hex)
        , Text.take 12 (Text.drop 20 hex)
        ]

normalizeLaneName :: Text -> Text
normalizeLaneName = Text.toCaseFold . Text.strip

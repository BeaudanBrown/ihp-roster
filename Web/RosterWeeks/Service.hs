module Web.RosterWeeks.Service
    ( RosterWeekSlotTemplate
    , appendRosterWeekSlotDefinition
    , copyRosterWeek
    , createEmptyRosterWeek
    , deleteRosterWeekSlotDefinition
    , ensureRosterDayHasMinimumRows
    , ensureRosterWeekExists
    , fetchRosterWeekSlotTemplate
    , fetchRosterWeekSlotTemplateFromSlots
    , fetchCurrentRosterWeekOffset
    , fetchRosterWeekOrderedSlotNames
    , fetchRosterWeekOrderedSlotNamesFromSlots
    , previewRemoveRosterRowPacking
    , replaceRosterWeekFromSource
    , removeRosterRowWithPacking
    , repackRosterWeekDays
    , rosterSlotHasData
    , rosterWeekSlotDefinitionHasData
    , RemoveRosterRowPackingPreview (..)
    ) where

import Application.Helper.RosterGroups
import Data.Coerce (coerce)
import Data.List (nub, sort, sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, isJust, isNothing, mapMaybe)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime, utctDay)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.UUID (UUID)
import qualified Database.PostgreSQL.Simple as PG
import IHP.ModelSupport (sqlExecDiscardResult)
import Web.Controller.Prelude
import Web.RosterWeeks.Dom (closedRosterDayRows, minimumOpenRosterRows)

data RemoveRosterRowPackingPreview = RemoveRosterRowPackingPreview
    { removeRosterRowLastRowIndex     :: !Int
    , removeRosterRowOverflowCount    :: !Int
    , removeRosterRowDeletedDataCount :: !Int
    }

data RosterSlotPlacement = RosterSlotPlacement
    { rosterSlotPlacementSlot       :: !RosterSlot
    , rosterSlotPlacementDefinition :: !RosterWeekSlotDefinition
    , rosterSlotPlacementRowIndex   :: !Int
    }

data RemoveRosterRowPackingPlan = RemoveRosterRowPackingPlan
    { removeRosterRowPlanLastRowIndex  :: !Int
    , removeRosterRowPlanPlacements    :: ![RosterSlotPlacement]
    , removeRosterRowPlanOverflowSlots :: ![RosterSlot]
    , removeRosterRowPlanDeleteSlots   :: ![RosterSlot]
    , removeRosterRowPlanTargetKeys    :: ![(UUID, Int)]
    , removeRosterRowPlanActiveDefIds  :: ![UUID]
    }

fetchCurrentRosterWeekOffset :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
fetchCurrentRosterWeekOffset = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    pure (venueWeekOffsetForDay venueConfig today)

type RosterWeekSlotTemplate = (RosterWeekSlotDefinition, Int)

fetchRosterWeekSlotTemplate :: (?modelContext :: ModelContext) => RosterWeek -> IO [RosterWeekSlotTemplate]
fetchRosterWeekSlotTemplate rosterWeek = do
    slotDefinitions <- fetchActiveRosterWeekSlotDefinitions rosterWeek
    pure (map (\slotDefinition -> (slotDefinition, slotDefinition.sortOrder)) slotDefinitions)

fetchRosterWeekSlotTemplateFromSlots :: (?modelContext :: ModelContext) => [RosterSlot] -> IO [RosterWeekSlotTemplate]
fetchRosterWeekSlotTemplateFromSlots allSlots = do
    let orderedSlotPairs =
            allSlots
                |> map (\slot -> (slot.rosterWeekSlotDefinitionId, slot.slotSortOrder))
                |> Map.fromListWith min
                |> Map.toList
                |> sortOn snd
    let orderedSlotIds = map fst orderedSlotPairs
    if null orderedSlotIds
        then pure []
        else do
            slotDefinitions <-
                query @RosterWeekSlotDefinition
                    |> filterWhereIn (#id, map Id orderedSlotIds)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
            let slotDefinitionById = Map.fromList (map (\slotDefinition -> (unpackId slotDefinition.id, slotDefinition)) slotDefinitions)
            pure
                [ (slotDefinition, slotSortOrder)
                | (slotNameId, slotSortOrder) <- orderedSlotPairs
                , Just slotDefinition <- [Map.lookup slotNameId slotDefinitionById]
                ]

fetchRosterWeekOrderedSlotNames :: (?modelContext :: ModelContext) => RosterWeek -> IO [RosterWeekSlotDefinition]
fetchRosterWeekOrderedSlotNames rosterWeek =
    map fst <$> fetchRosterWeekSlotTemplate rosterWeek

fetchRosterWeekOrderedSlotNamesFromSlots :: (?modelContext :: ModelContext) => [RosterSlot] -> IO [RosterWeekSlotDefinition]
fetchRosterWeekOrderedSlotNamesFromSlots allSlots =
    map fst <$> fetchRosterWeekSlotTemplateFromSlots allSlots

fetchActiveRosterWeekSlotDefinitions :: (?modelContext :: ModelContext) => RosterWeek -> IO [RosterWeekSlotDefinition]
fetchActiveRosterWeekSlotDefinitions rosterWeek =
    query @RosterWeekSlotDefinition
        |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
        |> filterWhere (#deletedAt, Nothing)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch

ensureRosterWeekExists :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO (RosterWeek, Bool)
ensureRosterWeekExists rosterGroupId weekOffset = do
    existing <- query @RosterWeek
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> filterWhere (#weekOffset, weekOffset)
        |> fetchOneOrNothing
    case existing of
        Just rosterWeek -> pure (rosterWeek, False)
        Nothing -> do
            rosterWeek <- createEmptyRosterWeek rosterGroupId weekOffset
            pure (rosterWeek, True)

createEmptyRosterWeek :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO RosterWeek
createEmptyRosterWeek rosterGroupId weekOffset = do
    rosterWeek <- newRecord @RosterWeek
        |> set #venueId (unpackId currentVenueId)
        |> set #rosterGroupId (unpackId rosterGroupId)
        |> set #weekOffset weekOffset
        |> set #isLive False
        |> createRecord

    sqlExecDiscardResult
        "INSERT INTO roster_days (roster_week_id, day_offset, is_closed) \
        \SELECT ?, day_offsets.day_offset, FALSE \
        \FROM generate_series(0, 6) AS day_offsets(day_offset)"
        (PG.Only (unpackId rosterWeek.id))

    createInitialRosterWeekSlotDefinitions rosterWeek

    pure rosterWeek

createInitialRosterWeekSlotDefinitions :: (?modelContext :: ModelContext) => RosterWeek -> IO ()
createInitialRosterWeekSlotDefinitions rosterWeek = do
    previousWeek <- query @RosterWeek
        |> filterWhere (#rosterGroupId, rosterWeek.rosterGroupId)
        |> filterWhereLessThan (#weekOffset, rosterWeek.weekOffset)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByDesc #weekOffset
        |> fetchOneOrNothing
    sourceDefinitions <-
        case previousWeek of
            Just sourceWeek -> fetchActiveRosterWeekSlotDefinitions sourceWeek
            Nothing         -> pure []
    if null sourceDefinitions
        then do
            rosterGroupSlotNames <- fetchActiveRosterGroupSlotNames (Id rosterWeek.rosterGroupId)
            let slotTemplates =
                    if null rosterGroupSlotNames
                        then zip defaultRosterSlotNames [0 :: Int ..]
                        else map (\slotName -> (slotName.name, slotName.sortOrder)) rosterGroupSlotNames
            forM_ slotTemplates \(slotName, sortOrder) -> do
                _ <- newRecord @RosterWeekSlotDefinition
                    |> set #rosterWeekId (unpackId rosterWeek.id)
                    |> set #name slotName
                    |> set #sortOrder sortOrder
                    |> createRecord
                pure ()
        else forM_ sourceDefinitions \sourceDefinition -> do
            _ <- newRecord @RosterWeekSlotDefinition
                |> set #rosterWeekId (unpackId rosterWeek.id)
                |> set #name sourceDefinition.name
                |> set #sortOrder sourceDefinition.sortOrder
                |> createRecord
            pure ()

copyRosterWeek :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWeek -> Int -> IO RosterWeek
copyRosterWeek sourceWeek targetWeekOffset = do
    targetWeek <- newRecord @RosterWeek
        |> set #venueId (unpackId currentVenueId)
        |> set #rosterGroupId sourceWeek.rosterGroupId
        |> set #weekOffset targetWeekOffset
        |> set #isLive False
        |> createRecord

    sqlExecDiscardResult
        "INSERT INTO roster_days (roster_week_id, day_offset, is_closed, row_count) \
        \SELECT ?, day_offsets.day_offset, COALESCE(source_days.is_closed, FALSE), COALESCE(source_days.row_count, 4) \
        \FROM generate_series(0, 6) AS day_offsets(day_offset) \
        \LEFT JOIN roster_days source_days \
        \    ON source_days.roster_week_id = ? \
        \    AND source_days.day_offset = day_offsets.day_offset \
        \ORDER BY day_offsets.day_offset"
        (unpackId targetWeek.id, unpackId sourceWeek.id)

    copyRosterWeekSlotDefinitionsAndSlots sourceWeek targetWeek

    pure targetWeek

replaceRosterWeekFromSource :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWeek -> RosterWeek -> IO RosterWeek
replaceRosterWeekFromSource sourceWeek targetWeek = do
    _ <- targetWeek
        |> set #isLive False
        |> updateRecord

    sqlExecDiscardResult
        "UPDATE roster_week_slot_definitions \
        \SET deleted_at = NOW(), delete_reason = 'roster_week_replaced', updated_at = NOW() \
        \WHERE roster_week_id = ? \
        \AND deleted_at IS NULL"
        (PG.Only (unpackId targetWeek.id))

    sqlExecDiscardResult
        "UPDATE roster_slots \
        \SET deleted_at = NOW(), delete_reason = 'roster_week_replaced', updated_at = NOW() \
        \FROM roster_days \
        \WHERE roster_slots.roster_day_id = roster_days.id \
        \AND roster_days.roster_week_id = ? \
        \AND roster_slots.deleted_at IS NULL"
        (PG.Only (unpackId targetWeek.id))

    copyRosterWeekSlotDefinitionsAndSlots sourceWeek targetWeek

    fetch targetWeek.id

ensureRosterDayHasMinimumRows :: (?modelContext :: ModelContext) => RosterDay -> Id RosterGroup -> Int -> IO ()
ensureRosterDayHasMinimumRows rosterDay _rosterGroupId minimumRowCount = do
    when (rosterDay.rowCount < minimumRowCount) do
        _ <- rosterDay
            |> set #rowCount minimumRowCount
            |> updateRecord
        pure ()

copyRosterWeekSlotDefinitionsAndSlots :: (?modelContext :: ModelContext) => RosterWeek -> RosterWeek -> IO ()
copyRosterWeekSlotDefinitionsAndSlots sourceWeek targetWeek = do
    sqlExecDiscardResult
        "UPDATE roster_days AS target_days \
        \SET row_count = source_days.row_count, updated_at = NOW() \
        \FROM roster_days AS source_days \
        \WHERE target_days.roster_week_id = ? \
        \AND source_days.roster_week_id = ? \
        \AND target_days.day_offset = source_days.day_offset"
        (unpackId targetWeek.id, unpackId sourceWeek.id)
    sqlExecDiscardResult
        "WITH inserted_definitions AS ( \
        \    INSERT INTO roster_week_slot_definitions (roster_week_id, name, sort_order) \
        \    SELECT ?, source_definitions.name, source_definitions.sort_order \
        \    FROM roster_week_slot_definitions source_definitions \
        \    WHERE source_definitions.roster_week_id = ? \
        \    AND source_definitions.deleted_at IS NULL \
        \    ORDER BY source_definitions.sort_order, source_definitions.created_at \
        \    RETURNING id, name, sort_order \
        \) \
        \INSERT INTO roster_slots (roster_day_id, staff_id, roster_week_slot_definition_id, slot_sort_order, row_index, start_time, end_time, shift_type_id, duration_minutes) \
        \SELECT target_days.id, source_slots.staff_id, inserted_definitions.id, inserted_definitions.sort_order, source_slots.row_index, source_slots.start_time, source_slots.end_time, source_slots.shift_type_id, source_slots.duration_minutes \
        \FROM roster_days source_days \
        \JOIN roster_slots source_slots ON source_slots.roster_day_id = source_days.id \
        \JOIN roster_week_slot_definitions source_definitions ON source_definitions.id = source_slots.roster_week_slot_definition_id \
        \JOIN inserted_definitions ON inserted_definitions.name = source_definitions.name AND inserted_definitions.sort_order = source_definitions.sort_order \
        \JOIN roster_days target_days \
        \    ON target_days.roster_week_id = ? \
        \    AND target_days.day_offset = source_days.day_offset \
        \WHERE source_days.roster_week_id = ? \
        \AND source_slots.deleted_at IS NULL \
        \AND (source_slots.staff_id IS NOT NULL \
        \    OR source_slots.start_time IS NOT NULL \
        \    OR source_slots.end_time IS NOT NULL \
        \    OR source_slots.shift_type_id IS NOT NULL \
        \    OR source_slots.duration_minutes IS NOT NULL) \
        \ORDER BY source_days.day_offset, source_slots.row_index, inserted_definitions.sort_order, source_slots.created_at"
        (unpackId targetWeek.id, unpackId sourceWeek.id, unpackId targetWeek.id, unpackId sourceWeek.id)

appendRosterWeekSlotDefinition :: (?modelContext :: ModelContext) => RosterWeek -> Text -> IO RosterWeekSlotDefinition
appendRosterWeekSlotDefinition rosterWeek slotName = do
    existingDefinitions <- fetchActiveRosterWeekSlotDefinitions rosterWeek
    let nextSortOrder = maybe 0 ((+ 1) . (.sortOrder)) (last existingDefinitions)
    newRecord @RosterWeekSlotDefinition
        |> set #rosterWeekId (unpackId rosterWeek.id)
        |> set #name slotName
        |> set #sortOrder nextSortOrder
        |> createRecord

rosterWeekSlotDefinitionHasData :: (?modelContext :: ModelContext) => RosterWeekSlotDefinition -> IO Bool
rosterWeekSlotDefinitionHasData slotDefinition = do
    slots <- query @RosterSlot
        |> filterWhere (#rosterWeekSlotDefinitionId, unpackId slotDefinition.id)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    pure (any rosterSlotHasData slots)

rosterSlotHasData :: RosterSlot -> Bool
rosterSlotHasData slot =
    isJust slot.staffId
        || isJust slot.startTime
        || isJust slot.endTime
        || isJust slot.shiftTypeId
        || isJust slot.durationMinutes

previewRemoveRosterRowPacking :: (?modelContext :: ModelContext) => RosterDay -> [RosterWeekSlotDefinition] -> IO RemoveRosterRowPackingPreview
previewRemoveRosterRowPacking rosterDay activeDefinitions = do
    activeSlots <- fetchActiveSlotsForDay rosterDay
    let plan = buildRemoveRosterRowPackingPlan rosterDay activeDefinitions activeSlots
    pure RemoveRosterRowPackingPreview
        { removeRosterRowLastRowIndex = removeRosterRowPlanLastRowIndex plan
        , removeRosterRowOverflowCount = length (removeRosterRowPlanOverflowSlots plan)
        , removeRosterRowDeletedDataCount = length (filter rosterSlotHasData (removeRosterRowPlanDeleteSlots plan))
        }

removeRosterRowWithPacking :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterDay -> [RosterWeekSlotDefinition] -> IO ()
removeRosterRowWithPacking rosterDay activeDefinitions = do
    activeSlots <- fetchActiveSlotsForDay rosterDay
    let plan = buildRemoveRosterRowPackingPlan rosterDay activeDefinitions activeSlots
    temporarilyMoveDataSlots activeSlots (map rosterSlotPlacementSlot (removeRosterRowPlanPlacements plan)) 1
    softDeleteRemoveRosterRowSlots plan activeSlots
    forM_ (removeRosterRowPlanPlacements plan) \placement -> do
        _ <- rosterSlotPlacementSlot placement
            |> set #rosterWeekSlotDefinitionId (unpackId (get #id (rosterSlotPlacementDefinition placement)))
            |> set #slotSortOrder (rosterSlotPlacementDefinition placement).sortOrder
            |> set #rowIndex (rosterSlotPlacementRowIndex placement)
            |> updateRecord
        pure ()
    _ <- rosterDay
        |> set #rowCount (max 0 (rosterDay.rowCount - 1))
        |> updateRecord
    pure ()

buildRemoveRosterRowPackingPlan :: RosterDay -> [RosterWeekSlotDefinition] -> [RosterSlot] -> RemoveRosterRowPackingPlan
buildRemoveRosterRowPackingPlan rosterDay activeDefinitions activeSlots =
    RemoveRosterRowPackingPlan
        { removeRosterRowPlanLastRowIndex = lastRowIndex
        , removeRosterRowPlanPlacements = retainedPlacements <> incomingPlacements
        , removeRosterRowPlanOverflowSlots = overflowSlots
        , removeRosterRowPlanDeleteSlots = deletedRowSlots
        , removeRosterRowPlanTargetKeys = map (\placement -> (unpackId (get #id (rosterSlotPlacementDefinition placement)), rosterSlotPlacementRowIndex placement)) (retainedPlacements <> incomingPlacements)
        , removeRosterRowPlanActiveDefIds = activeDefinitionIds
        }
    where
        activeDefinitionIds = map (unpackId . (.id)) activeDefinitions
        activeTemplateSlots = filter (\slot -> slot.rosterWeekSlotDefinitionId `elem` activeDefinitionIds) activeSlots
        lastRowIndex = rosterDay.rowCount - 1
        targetRowCount = max 0 lastRowIndex
        deletedRowSlots =
            filter (\slot -> slot.rowIndex == lastRowIndex && slot.rosterWeekSlotDefinitionId `elem` activeDefinitionIds) activeTemplateSlots
        incomingSlots =
            sortOn (definitionOrderKey activeDefinitions) (filter rosterSlotHasData deletedRowSlots)
        retainedPlacements =
            concatMap retainedPlacementsForDefinition activeDefinitions
        freeCells =
            concatMap freeCellsForDefinition activeDefinitions
        incomingPlacements =
            zipWith
                (\slot (slotDefinition, rowIndex) -> RosterSlotPlacement slot slotDefinition rowIndex)
                incomingSlots
                freeCells
        overflowSlots = drop (length freeCells) incomingSlots
        retainedPlacementsForDefinition slotDefinition =
            zipWith
                (\rowIndex slot -> RosterSlotPlacement slot slotDefinition rowIndex)
                [0 ..]
                (retainedDataSlotsForDefinition slotDefinition)
        retainedDataSlotsForDefinition slotDefinition =
            activeTemplateSlots
                |> filter (\slot -> slot.rowIndex < lastRowIndex && slot.rosterWeekSlotDefinitionId == unpackId slotDefinition.id && rosterSlotHasData slot)
                |> sortOn (.rowIndex)
        freeCellsForDefinition slotDefinition =
            let retainedCount = length (retainedDataSlotsForDefinition slotDefinition)
             in [ (slotDefinition, rowIndex)
                | rowIndex <- [retainedCount .. targetRowCount - 1]
                ]

definitionOrderKey :: [RosterWeekSlotDefinition] -> RosterSlot -> (Int, Int, UTCTime, Id RosterSlot)
definitionOrderKey activeDefinitions slot =
    ( Map.findWithDefault slot.slotSortOrder slot.rosterWeekSlotDefinitionId definitionSortOrderById
    , slot.rowIndex
    , slot.createdAt
    , slot.id
    )
    where
        definitionSortOrderById =
            Map.fromList
                [ (unpackId slotDefinition.id, slotDefinition.sortOrder)
                | slotDefinition <- activeDefinitions
                ]

softDeleteRemoveRosterRowSlots :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RemoveRosterRowPackingPlan -> [RosterSlot] -> IO ()
softDeleteRemoveRosterRowSlots plan activeSlots = do
    now <- getCurrentTime
    let placementSlotIds = map (unpackId . get #id . rosterSlotPlacementSlot) (removeRosterRowPlanPlacements plan)
    let overflowSlotIds = map (unpackId . get #id) (removeRosterRowPlanOverflowSlots plan)
    let activeDefinitionIds = removeRosterRowPlanActiveDefIds plan
    let lastRowIndex = removeRosterRowPlanLastRowIndex plan
    let shouldDelete slot =
            unpackId slot.id `elem` overflowSlotIds
                || ( slot.rosterWeekSlotDefinitionId `elem` activeDefinitionIds
                    && slot.rowIndex >= lastRowIndex
                    && unpackId slot.id `notElem` placementSlotIds
                   )
                || not (rosterSlotHasData slot)
    forM_ (filter shouldDelete activeSlots) \slot -> do
        _ <- slot
            |> set #deletedAt (Just now)
            |> set #deletedByUserId (Just (unpackId currentUser.id))
            |> set #deleteReason (Just "roster_row_removed")
            |> updateRecord
        pure ()

repackRosterWeekDays :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWeek -> IO ()
repackRosterWeekDays rosterWeek = do
    activeDefinitions <- fetchActiveRosterWeekSlotDefinitions rosterWeek
    unless (null activeDefinitions) do
        rosterDays <- query @RosterDay
            |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
            |> orderByAsc #dayOffset
            |> fetch
        forM_ rosterDays (repackRosterDay activeDefinitions)

repackRosterDay :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => [RosterWeekSlotDefinition] -> RosterDay -> IO ()
repackRosterDay activeDefinitions rosterDay = do
    initialSlots <- fetchActiveSlotsForDay rosterDay
    let activeDefinitionIds = map (unpackId . (.id)) activeDefinitions
    let minimumRows =
            if rosterDay.isClosed
                then closedRosterDayRows
                else minimumOpenRosterRows
    let requiredRows =
            max
                minimumRows
                (ceilingDiv (length (filter rosterSlotHasData initialSlots)) (length activeDefinitions))

    _ <- rosterDay
        |> set #rowCount requiredRows
        |> updateRecord
    activeSlots <- fetchActiveSlotsForDay rosterDay
    staffById <- fetchStaffLabelsById activeSlots
    let definitionSortOrderById =
            Map.fromList
                [ (unpackId slotDefinition.id, slotDefinition.sortOrder)
                | slotDefinition <- activeDefinitions
                ]
    let dataSlots = sortOn (slotPackingKey definitionSortOrderById staffById) (filter rosterSlotHasData activeSlots)
    let targetCells =
            [ (slotDefinition, rowIndex)
            | slotDefinition <- activeDefinitions
            , rowIndex <- [0 .. requiredRows - 1]
            ]
    let placements = zip dataSlots targetCells

    temporarilyMoveDataSlots activeSlots dataSlots requiredRows
    softDeleteDisplacedBlankSlots activeDefinitionIds (map snd placements) activeSlots
    forM_ placements \(slot, (slotDefinition, rowIndex)) -> do
        _ <- slot
            |> set #rosterWeekSlotDefinitionId (unpackId slotDefinition.id)
            |> set #slotSortOrder slotDefinition.sortOrder
            |> set #rowIndex rowIndex
            |> updateRecord
        pure ()

fetchActiveSlotsForDay :: (?modelContext :: ModelContext) => RosterDay -> IO [RosterSlot]
fetchActiveSlotsForDay rosterDay =
    query @RosterSlot
        |> filterWhere (#rosterDayId, unpackId rosterDay.id)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch

fetchStaffLabelsById :: (?modelContext :: ModelContext) => [RosterSlot] -> IO (Map.Map UUID Text)
fetchStaffLabelsById slots = do
    let staffIds = nub (mapMaybe (.staffId) slots)
    if null staffIds
        then pure Map.empty
        else do
            staffMembers <- query @Staff
                |> filterWhereIn (#id, map Id staffIds)
                |> fetch
            pure (Map.fromList (map (\staff -> (unpackId staff.id, staffSortLabel staff)) staffMembers))

staffSortLabel :: Staff -> Text
staffSortLabel staff =
    Text.toCaseFold (fromMaybe staff.firstName staff.preferredName <> " " <> staff.lastName)

slotPackingKey :: Map.Map UUID Int -> Map.Map UUID Text -> RosterSlot -> (Bool, TimeOfDay, Text, Int, Int, UTCTime, Id RosterSlot)
slotPackingKey definitionSortOrderById staffById slot =
    ( isNothing slot.startTime
    , fromMaybe (TimeOfDay 23 59 59) slot.startTime
    , fromMaybe "\xffff" (slot.staffId >>= (`Map.lookup` staffById))
    , slot.rowIndex
    , Map.findWithDefault slot.slotSortOrder slot.rosterWeekSlotDefinitionId definitionSortOrderById
    , slot.createdAt
    , slot.id
    )

temporarilyMoveDataSlots :: (?modelContext :: ModelContext) => [RosterSlot] -> [RosterSlot] -> Int -> IO ()
temporarilyMoveDataSlots activeSlots dataSlots requiredRows = do
    let maxExistingRowIndex = fromMaybe 0 (nonEmptyMaximum (map (.rowIndex) activeSlots))
    let temporaryRowStart = maxExistingRowIndex + requiredRows + length dataSlots + 100
    forM_ (zip [0 :: Int ..] dataSlots) \(index, slot) -> do
        _ <- slot
            |> set #rowIndex (temporaryRowStart + index)
            |> updateRecord
        pure ()

nonEmptyMaximum :: Ord a => [a] -> Maybe a
nonEmptyMaximum []     = Nothing
nonEmptyMaximum values = Just (maximum values)

softDeleteDisplacedBlankSlots :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => [UUID] -> [(RosterWeekSlotDefinition, Int)] -> [RosterSlot] -> IO ()
softDeleteDisplacedBlankSlots activeDefinitionIds _ activeSlots = do
    now <- getCurrentTime
    let shouldDelete slot =
            not (rosterSlotHasData slot)
                && slot.rosterWeekSlotDefinitionId `notElem` activeDefinitionIds
    forM_ (filter shouldDelete activeSlots) \slot -> do
        _ <- slot
            |> set #deletedAt (Just now)
            |> set #deletedByUserId (Just (unpackId currentUser.id))
            |> set #deleteReason (Just "roster_slots_repacked")
            |> updateRecord
        pure ()

ceilingDiv :: Int -> Int -> Int
ceilingDiv _ 0 = 0
ceilingDiv numerator denominator =
    (numerator + denominator - 1) `div` denominator

deleteRosterWeekSlotDefinition :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWeekSlotDefinition -> IO ()
deleteRosterWeekSlotDefinition slotDefinition = do
    now <- getCurrentTime
    _ <- slotDefinition
        |> set #deletedAt (Just now)
        |> set #deletedByUserId (Just (unpackId currentUser.id))
        |> set #deleteReason (Just "roster_slot_definition_removed")
        |> updateRecord
    rosterWeek <- fetch (Id slotDefinition.rosterWeekId :: Id RosterWeek)
    repackRosterWeekDays rosterWeek

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
    , replaceRosterWeekFromSource
    , repackRosterWeekDays
    , rosterSlotHasData
    , rosterWeekSlotDefinitionHasData
    ) where

import Application.Helper.RosterGroups
import Data.Coerce (coerce)
import Data.List (nub, sort, sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime, utctDay)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.UUID (UUID)
import qualified Database.PostgreSQL.Simple as PG
import IHP.ModelSupport (sqlExecDiscardResult)
import Web.RosterWeeks.Dom (closedRosterDayRows, minimumOpenRosterRows)
import Web.Controller.Prelude

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

    sqlExecDiscardResult
        "INSERT INTO roster_slots (roster_day_id, roster_week_slot_definition_id, slot_sort_order, row_index) \
        \SELECT roster_days.id, slot_definitions.id, slot_definitions.sort_order, row_indexes.row_index \
        \FROM roster_days \
        \CROSS JOIN generate_series(0, 3) AS row_indexes(row_index) \
        \JOIN roster_week_slot_definitions slot_definitions ON slot_definitions.roster_week_id = ? AND slot_definitions.deleted_at IS NULL \
        \WHERE roster_days.roster_week_id = ? \
        \ORDER BY roster_days.day_offset, row_indexes.row_index, slot_definitions.sort_order, slot_definitions.created_at"
        (unpackId rosterWeek.id, unpackId rosterWeek.id)

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
        then forM_ (zip [0 :: Int ..] defaultRosterSlotNames) \(sortOrder, slotName) -> do
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
        "INSERT INTO roster_days (roster_week_id, day_offset, is_closed) \
        \SELECT ?, day_offsets.day_offset, COALESCE(source_days.is_closed, FALSE) \
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
    rosterWeek <- fetch (Id rosterDay.rosterWeekId :: Id RosterWeek)
    sqlExecDiscardResult
        "INSERT INTO roster_slots (roster_day_id, roster_week_slot_definition_id, slot_sort_order, row_index) \
        \SELECT ?, template_slots.roster_week_slot_definition_id, template_slots.slot_sort_order, row_indexes.row_index \
        \FROM generate_series(0, ?) AS row_indexes(row_index) \
        \JOIN ( \
        \    SELECT id AS roster_week_slot_definition_id, sort_order AS slot_sort_order \
        \    FROM roster_week_slot_definitions \
        \    WHERE roster_week_id = ? \
        \    AND deleted_at IS NULL \
        \) template_slots ON TRUE \
        \WHERE NOT EXISTS ( \
        \    SELECT 1 FROM roster_slots existing_slot \
        \    WHERE existing_slot.roster_day_id = ? \
        \    AND existing_slot.row_index = row_indexes.row_index \
        \    AND existing_slot.roster_week_slot_definition_id = template_slots.roster_week_slot_definition_id \
        \    AND existing_slot.deleted_at IS NULL \
        \)"
        (unpackId rosterDay.id, minimumRowCount - 1, unpackId rosterWeek.id, unpackId rosterDay.id)

copyRosterWeekSlotDefinitionsAndSlots :: (?modelContext :: ModelContext) => RosterWeek -> RosterWeek -> IO ()
copyRosterWeekSlotDefinitionsAndSlots sourceWeek targetWeek = do
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
        \INSERT INTO roster_slots (roster_day_id, staff_id, roster_week_slot_definition_id, slot_sort_order, row_index, start_time, end_time, shift_type_id, duration_minutes, note) \
        \SELECT target_days.id, source_slots.staff_id, inserted_definitions.id, inserted_definitions.sort_order, source_slots.row_index, source_slots.start_time, source_slots.end_time, source_slots.shift_type_id, source_slots.duration_minutes, source_slots.note \
        \FROM roster_days source_days \
        \JOIN roster_slots source_slots ON source_slots.roster_day_id = source_days.id \
        \JOIN roster_week_slot_definitions source_definitions ON source_definitions.id = source_slots.roster_week_slot_definition_id \
        \JOIN inserted_definitions ON inserted_definitions.name = source_definitions.name AND inserted_definitions.sort_order = source_definitions.sort_order \
        \JOIN roster_days target_days \
        \    ON target_days.roster_week_id = ? \
        \    AND target_days.day_offset = source_days.day_offset \
        \WHERE source_days.roster_week_id = ? \
        \AND source_slots.deleted_at IS NULL \
        \ORDER BY source_days.day_offset, source_slots.row_index, inserted_definitions.sort_order, source_slots.created_at"
        (unpackId targetWeek.id, unpackId sourceWeek.id, unpackId targetWeek.id, unpackId sourceWeek.id)

appendRosterWeekSlotDefinition :: (?modelContext :: ModelContext) => RosterWeek -> Text -> IO RosterWeekSlotDefinition
appendRosterWeekSlotDefinition rosterWeek slotName = do
    existingDefinitions <- fetchActiveRosterWeekSlotDefinitions rosterWeek
    let nextSortOrder = maybe 0 ((+ 1) . (.sortOrder)) (last existingDefinitions)
    slotDefinition <-
        newRecord @RosterWeekSlotDefinition
            |> set #rosterWeekId (unpackId rosterWeek.id)
            |> set #name slotName
            |> set #sortOrder nextSortOrder
            |> createRecord
    sqlExecDiscardResult
        "INSERT INTO roster_slots (roster_day_id, roster_week_slot_definition_id, slot_sort_order, row_index) \
        \SELECT roster_days.id, ?, ?, existing_rows.row_index \
        \FROM roster_days \
        \JOIN ( \
        \    SELECT DISTINCT roster_slots.roster_day_id, roster_slots.row_index \
        \    FROM roster_slots \
        \    JOIN roster_days existing_days ON existing_days.id = roster_slots.roster_day_id \
        \    WHERE existing_days.roster_week_id = ? \
        \    AND roster_slots.deleted_at IS NULL \
        \) existing_rows ON existing_rows.roster_day_id = roster_days.id \
        \WHERE roster_days.roster_week_id = ? \
        \AND NOT EXISTS ( \
        \    SELECT 1 FROM roster_slots existing_slot \
        \    WHERE existing_slot.roster_day_id = roster_days.id \
        \    AND existing_slot.row_index = existing_rows.row_index \
        \    AND existing_slot.roster_week_slot_definition_id = ? \
        \    AND existing_slot.deleted_at IS NULL \
        \)"
        (unpackId slotDefinition.id, slotDefinition.sortOrder, unpackId rosterWeek.id, unpackId rosterWeek.id, unpackId slotDefinition.id)
    pure slotDefinition

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
        || isJust slot.note

repackRosterWeekDays :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWeek -> IO ()
repackRosterWeekDays rosterWeek = do
    activeDefinitions <- fetchActiveRosterWeekSlotDefinitions rosterWeek
    when (not (null activeDefinitions)) do
        rosterDays <- query @RosterDay
            |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
            |> orderByAsc #dayOffset
            |> fetch
        forM_ rosterDays (repackRosterDay rosterWeek activeDefinitions)

repackRosterDay :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWeek -> [RosterWeekSlotDefinition] -> RosterDay -> IO ()
repackRosterDay rosterWeek activeDefinitions rosterDay = do
    initialSlots <- fetchActiveSlotsForDay rosterDay
    let activeDefinitionIds = map (unpackId . (.id)) activeDefinitions
    let existingActiveRowIndices =
            [ slot.rowIndex
            | slot <- initialSlots
            , slot.rosterWeekSlotDefinitionId `elem` activeDefinitionIds
            ]
    let minimumRows =
            if rosterDay.isClosed
                then closedRosterDayRows
                else minimumOpenRosterRows
    let requiredRows =
            maximum
                [ minimumRows
                , maybe 0 (+ 1) (last (sort existingActiveRowIndices))
                , ceilingDiv (length (filter rosterSlotHasData initialSlots)) (length activeDefinitions)
                ]

    ensureRosterDayHasMinimumRows rosterDay (coerce rosterWeek.rosterGroupId) requiredRows
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
    let staffIds = nub (catMaybes (map (.staffId) slots))
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
    let maxExistingRowIndex = fromMaybe 0 (last (sort (map (.rowIndex) activeSlots)))
    let temporaryRowStart = maxExistingRowIndex + requiredRows + length dataSlots + 100
    forM_ (zip [0 :: Int ..] dataSlots) \(index, slot) -> do
        _ <- slot
            |> set #rowIndex (temporaryRowStart + index)
            |> updateRecord
        pure ()

softDeleteDisplacedBlankSlots :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => [UUID] -> [(RosterWeekSlotDefinition, Int)] -> [RosterSlot] -> IO ()
softDeleteDisplacedBlankSlots activeDefinitionIds targetCells activeSlots = do
    now <- getCurrentTime
    let targetCellKeys =
            [ (unpackId slotDefinition.id, rowIndex)
            | (slotDefinition, rowIndex) <- targetCells
            ]
    let shouldDelete slot =
            not (rosterSlotHasData slot)
                && ( slot.rosterWeekSlotDefinitionId `notElem` activeDefinitionIds
                    || (slot.rosterWeekSlotDefinitionId, slot.rowIndex) `elem` targetCellKeys
                   )
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

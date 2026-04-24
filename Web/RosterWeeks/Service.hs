module Web.RosterWeeks.Service
    ( RosterWeekSlotTemplate
    , copyRosterWeek
    , createEmptyRosterWeek
    , ensureRosterDayHasMinimumRows
    , ensureRosterWeekExists
    , fetchCurrentRosterWeekOffset
    , fetchRosterWeekOrderedSlotNames
    , fetchRosterWeekOrderedSlotNamesFromSlots
    , fetchRosterWeekSlotTemplate
    , fetchRosterWeekSlotTemplateFromSlots
    , syncRosterWeekSlotStructure
    ) where

import Application.Helper.RosterGroups
import Data.Coerce (coerce)
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Time (getCurrentTime, utctDay)
import qualified Database.PostgreSQL.Simple as PG
import IHP.ModelSupport (sqlExecDiscardResult)
import Web.Controller.Prelude

fetchCurrentRosterWeekOffset :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
fetchCurrentRosterWeekOffset = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    pure (venueWeekOffsetForDay venueConfig today)

type RosterWeekSlotTemplate = (SlotName, Int)

fetchRosterWeekSlotTemplate :: (?modelContext :: ModelContext) => RosterWeek -> IO [RosterWeekSlotTemplate]
fetchRosterWeekSlotTemplate rosterWeek = do
    rosterDays <-
        query @RosterDay
            |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
            |> fetch
    if null rosterDays
        then pure []
        else do
            allSlots <-
                query @RosterSlot
                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                    |> fetch
            fetchRosterWeekSlotTemplateFromSlots allSlots

fetchRosterWeekSlotTemplateFromSlots :: (?modelContext :: ModelContext) => [RosterSlot] -> IO [RosterWeekSlotTemplate]
fetchRosterWeekSlotTemplateFromSlots allSlots = do
    let orderedSlotPairs =
            allSlots
                |> map (\slot -> (slot.slotNameId, slot.slotSortOrder))
                |> Map.fromListWith min
                |> Map.toList
                |> sortOn snd
    let orderedSlotIds = map fst orderedSlotPairs
    if null orderedSlotIds
        then pure []
        else do
            slotNames <-
                query @SlotName
                    |> filterWhereIn (#id, map Id orderedSlotIds)
                    |> fetch
            let slotNameById = Map.fromList (map (\slotName -> (unpackId slotName.id, slotName)) slotNames)
            pure
                [ (slotName, slotSortOrder)
                | (slotNameId, slotSortOrder) <- orderedSlotPairs
                , Just slotName <- [Map.lookup slotNameId slotNameById]
                ]

fetchRosterWeekOrderedSlotNames :: (?modelContext :: ModelContext) => RosterWeek -> IO [SlotName]
fetchRosterWeekOrderedSlotNames rosterWeek =
    map fst <$> fetchRosterWeekSlotTemplate rosterWeek

fetchRosterWeekOrderedSlotNamesFromSlots :: (?modelContext :: ModelContext) => [RosterSlot] -> IO [SlotName]
fetchRosterWeekOrderedSlotNamesFromSlots allSlots =
    map fst <$> fetchRosterWeekSlotTemplateFromSlots allSlots

syncRosterWeekSlotStructure :: (?modelContext :: ModelContext) => RosterWeek -> IO ()
syncRosterWeekSlotStructure rosterWeek = do
    sqlExecDiscardResult
        "INSERT INTO roster_slots (roster_day_id, slot_name_id, slot_sort_order, row_index) \
        \SELECT roster_days.id, slot_names.id, slot_names.sort_order, existing_rows.row_index \
        \FROM roster_days \
        \JOIN ( \
        \    SELECT DISTINCT roster_slots.roster_day_id, roster_slots.row_index \
        \    FROM roster_slots \
        \    JOIN roster_days existing_days ON existing_days.id = roster_slots.roster_day_id \
        \    WHERE existing_days.roster_week_id = ? \
        \) existing_rows ON existing_rows.roster_day_id = roster_days.id \
        \JOIN slot_names ON slot_names.roster_group_id = ? AND slot_names.is_active = TRUE \
        \WHERE roster_days.roster_week_id = ? \
        \AND NOT EXISTS ( \
        \    SELECT 1 FROM roster_slots existing_slot \
        \    WHERE existing_slot.roster_day_id = roster_days.id \
        \    AND existing_slot.row_index = existing_rows.row_index \
        \    AND existing_slot.slot_name_id = slot_names.id \
        \)"
        (unpackId rosterWeek.id, rosterWeek.rosterGroupId, unpackId rosterWeek.id)

    sqlExecDiscardResult
        "DELETE FROM roster_slots \
        \USING roster_days \
        \WHERE roster_slots.roster_day_id = roster_days.id \
        \AND roster_days.roster_week_id = ? \
        \AND NOT EXISTS ( \
        \    SELECT 1 FROM slot_names \
        \    WHERE slot_names.id = roster_slots.slot_name_id \
        \    AND slot_names.roster_group_id = ? \
        \    AND slot_names.is_active = TRUE \
        \)"
        (unpackId rosterWeek.id, rosterWeek.rosterGroupId)

    sqlExecDiscardResult
        "UPDATE roster_slots \
        \SET slot_sort_order = slot_names.sort_order, updated_at = NOW() \
        \FROM roster_days, slot_names \
        \WHERE roster_slots.roster_day_id = roster_days.id \
        \AND roster_slots.slot_name_id = slot_names.id \
        \AND roster_days.roster_week_id = ? \
        \AND slot_names.roster_group_id = ? \
        \AND slot_names.is_active = TRUE \
        \AND roster_slots.slot_sort_order <> slot_names.sort_order"
        (unpackId rosterWeek.id, rosterWeek.rosterGroupId)

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

    sqlExecDiscardResult
        "INSERT INTO roster_slots (roster_day_id, slot_name_id, slot_sort_order, row_index) \
        \SELECT roster_days.id, slot_names.id, slot_names.sort_order, row_indexes.row_index \
        \FROM roster_days \
        \CROSS JOIN generate_series(0, 3) AS row_indexes(row_index) \
        \JOIN slot_names ON slot_names.roster_group_id = ? AND slot_names.is_active = TRUE \
        \WHERE roster_days.roster_week_id = ? \
        \ORDER BY roster_days.day_offset, row_indexes.row_index, slot_names.sort_order, slot_names.created_at"
        (unpackId rosterGroupId, unpackId rosterWeek.id)

    pure rosterWeek

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

    sqlExecDiscardResult
        "INSERT INTO roster_slots (roster_day_id, staff_id, slot_name_id, slot_sort_order, row_index, start_time, duration_minutes, note) \
        \SELECT target_days.id, source_slots.staff_id, source_slots.slot_name_id, source_slots.slot_sort_order, source_slots.row_index, source_slots.start_time, source_slots.duration_minutes, source_slots.note \
        \FROM roster_days source_days \
        \JOIN roster_slots source_slots ON source_slots.roster_day_id = source_days.id \
        \JOIN roster_days target_days \
        \    ON target_days.roster_week_id = ? \
        \    AND target_days.day_offset = source_days.day_offset \
        \WHERE source_days.roster_week_id = ? \
        \ORDER BY source_days.day_offset, source_slots.row_index, source_slots.slot_sort_order, source_slots.created_at"
        (unpackId targetWeek.id, unpackId sourceWeek.id)

    pure targetWeek

ensureRosterDayHasMinimumRows :: (?modelContext :: ModelContext) => RosterDay -> Id RosterGroup -> Int -> IO ()
ensureRosterDayHasMinimumRows rosterDay _rosterGroupId minimumRowCount = do
    rosterWeek <- fetch (Id rosterDay.rosterWeekId :: Id RosterWeek)
    sqlExecDiscardResult
        "INSERT INTO roster_slots (roster_day_id, slot_name_id, slot_sort_order, row_index) \
        \SELECT ?, template_slots.slot_name_id, template_slots.slot_sort_order, row_indexes.row_index \
        \FROM generate_series(0, ?) AS row_indexes(row_index) \
        \JOIN ( \
        \    SELECT roster_slots.slot_name_id, MIN(roster_slots.slot_sort_order) AS slot_sort_order \
        \    FROM roster_slots \
        \    JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
        \    WHERE roster_days.roster_week_id = ? \
        \    GROUP BY roster_slots.slot_name_id \
        \) template_slots ON TRUE \
        \WHERE NOT EXISTS ( \
        \    SELECT 1 FROM roster_slots existing_slot \
        \    WHERE existing_slot.roster_day_id = ? \
        \    AND existing_slot.row_index = row_indexes.row_index \
        \    AND existing_slot.slot_name_id = template_slots.slot_name_id \
        \)"
        (unpackId rosterDay.id, minimumRowCount - 1, unpackId rosterWeek.id, unpackId rosterDay.id)

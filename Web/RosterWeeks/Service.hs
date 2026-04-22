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
import Data.List (find, nub, sortOn)
import qualified Data.Map.Strict as Map
import Data.Time (getCurrentTime, utctDay)
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
    currentSlotTemplate <- fetchActiveRosterGroupSlotNames (Id rosterWeek.rosterGroupId :: Id RosterGroup)
    rosterDays <-
        query @RosterDay
            |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
            |> fetch

    let currentSlotIds = map (unpackId . (.id)) currentSlotTemplate
    let sortOrderBySlotId = Map.fromList (map (\slotName -> (unpackId slotName.id, slotName.sortOrder)) currentSlotTemplate)

    forM_ rosterDays \rosterDay -> do
        existingSlots <-
            query @RosterSlot
                |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                |> fetch

        let existingRowIndexes = nub (map (.rowIndex) existingSlots)
        let obsoleteSlots = filter (\slot -> slot.slotNameId `notElem` currentSlotIds) existingSlots
        unless (null obsoleteSlots) do
            deleteRecords obsoleteSlots

        forM_ existingSlots \slot ->
            case Map.lookup slot.slotNameId sortOrderBySlotId of
                Just slotSortOrder | slot.slotSortOrder /= slotSortOrder -> do
                    _ <- slot |> set #slotSortOrder slotSortOrder |> updateRecord
                    pure ()
                _ -> pure ()

        let retainedSlotPairs =
                [ (rowIndex, slotName)
                | rowIndex <- existingRowIndexes
                , slotName <- currentSlotTemplate
                ]

        forM_ retainedSlotPairs \(rowIndex, slotName) ->
            when (isNothing (find (\slot -> slot.rowIndex == rowIndex && slot.slotNameId == unpackId slotName.id) existingSlots)) do
                _ <-
                    newRecord @RosterSlot
                        |> set #rosterDayId (unpackId rosterDay.id)
                        |> set #slotNameId (unpackId slotName.id)
                        |> set #slotSortOrder slotName.sortOrder
                        |> set #rowIndex rowIndex
                        |> createRecord
                pure ()

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
    orderedSlotNames <- fetchActiveRosterGroupSlotNames rosterGroupId

    rosterWeek <- newRecord @RosterWeek
        |> set #venueId (unpackId currentVenueId)
        |> set #rosterGroupId (unpackId rosterGroupId)
        |> set #weekOffset weekOffset
        |> set #isLive False
        |> createRecord

    forM_ [0 .. 6] \dayOffset -> do
        rosterDay <- newRecord @RosterDay
            |> set #rosterWeekId (coerce (get #id rosterWeek))
            |> set #dayOffset dayOffset
            |> set #isClosed False
            |> createRecord

        forM_ [0 .. 3] \rowIndex ->
            forM_ orderedSlotNames \slotName -> do
                newRecord @RosterSlot
                    |> set #rosterDayId (coerce (get #id rosterDay))
                    |> set #slotNameId (coerce (get #id slotName))
                    |> set #slotSortOrder slotName.sortOrder
                    |> set #rowIndex rowIndex
                    |> createRecord

    pure rosterWeek

copyRosterWeek :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWeek -> Int -> IO RosterWeek
copyRosterWeek sourceWeek targetWeekOffset = do
    targetWeek <- newRecord @RosterWeek
        |> set #venueId (unpackId currentVenueId)
        |> set #rosterGroupId sourceWeek.rosterGroupId
        |> set #weekOffset targetWeekOffset
        |> set #isLive False
        |> createRecord

    sourceDays <- query @RosterDay
        |> filterWhere (Proxy @"rosterWeekId", coerce (get #id sourceWeek))
        |> fetch

    forM_ [0 .. 6] \dayOffset -> do
        let maybeSourceDay = find (\day -> get #dayOffset day == dayOffset) sourceDays
        targetDay <- newRecord @RosterDay
            |> set #rosterWeekId (coerce (get #id targetWeek))
            |> set #dayOffset dayOffset
            |> set #isClosed (maybe False (.isClosed) maybeSourceDay)
            |> createRecord

        case maybeSourceDay of
            Just sourceDay -> do
                sourceSlots <- query @RosterSlot
                    |> filterWhere (#rosterDayId, coerce (get #id sourceDay))
                    |> fetch
                forM_ sourceSlots \slot -> do
                    newRecord @RosterSlot
                        |> set #rosterDayId (coerce (get #id targetDay))
                        |> set #staffId slot.staffId
                        |> set #slotNameId slot.slotNameId
                        |> set #slotSortOrder slot.slotSortOrder
                        |> set #rowIndex slot.rowIndex
                        |> set #startTime slot.startTime
                        |> set #durationMinutes slot.durationMinutes
                        |> set #note slot.note
                        |> createRecord
                    pure ()
            Nothing -> pure ()

    pure targetWeek

ensureRosterDayHasMinimumRows :: (?modelContext :: ModelContext) => RosterDay -> Id RosterGroup -> Int -> IO ()
ensureRosterDayHasMinimumRows rosterDay _rosterGroupId minimumRowCount = do
    rosterWeek <- fetch (Id rosterDay.rosterWeekId :: Id RosterWeek)
    existingSlots <- query @RosterSlot
        |> filterWhere (#rosterDayId, unpackId rosterDay.id)
        |> fetch

    slotTemplate <- fetchRosterWeekSlotTemplate rosterWeek

    forM_ [0 .. minimumRowCount - 1] \rowIndex ->
        forM_ slotTemplate \(slotName, slotSortOrder) ->
            when (isNothing (find (\slot -> slot.rowIndex == rowIndex && slot.slotNameId == unpackId slotName.id) existingSlots)) do
                _ <- newRecord @RosterSlot
                    |> set #rosterDayId (unpackId rosterDay.id)
                    |> set #slotNameId (unpackId slotName.id)
                    |> set #slotSortOrder slotSortOrder
                    |> set #rowIndex rowIndex
                    |> createRecord
                pure ()

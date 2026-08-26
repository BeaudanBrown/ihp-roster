{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.RosterWeeks.TemplateApplication.Persistence
    ( applyPreparedApplication
    ) where

import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          applyRosterShiftAssignment)
import Application.RosterTemplates (RosterTemplateActor,
                                    RosterTemplateSaved (..),
                                    rosterTemplateActorUserId)
import Application.VenueTime (melbourneTimeZoneName)
import Control.Monad (void)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import Web.RosterWeeks.TemplateApplication.Types

applyPreparedApplication ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    PreparedApplication ->
    IO Int
applyPreparedApplication actor prepared = do
    now <- getCurrentTime
    forM_ prepared.preparedExistingSlots \slot ->
        slot
            |> set #deletedAt (Just now)
            |> set #deletedByUserId (Just (unpackId (rosterTemplateActorUserId actor)))
            |> set #deleteReason (Just "roster_template_applied")
            |> updateRecord
            |> void
    appliedVersion <- persistCleanedTemplateVersion actor prepared
    applyDayStates prepared
    lanes <- ensureTargetLanes prepared
    let laneByDayAndName = Map.fromList [((lane.rosterDayId, Text.toCaseFold (Text.strip lane.name)), lane) | lane <- lanes]
    forM_ prepared.preparedShiftPlans \plan -> do
        let lane = laneByDayAndName Map.! (unpackId plan.preparedTargetDay.id, Text.toCaseFold (Text.strip plan.preparedTemplateColumn.name))
        newRecord @RosterSlot
            |> set #rosterDayId (unpackId plan.preparedTargetDay.id)
            |> set #rosterLaneId (unpackId lane.id)
            |> set #slotSortOrder lane.sortOrder
            |> set #rowIndex plan.preparedTemplateShift.rowIndex
            |> set #startsAt (Just plan.preparedStartsAt)
            |> set #endsAt (Just plan.preparedEndsAt)
            |> set #timezone melbourneTimeZoneName
            |> set #shiftTypeId (Just plan.preparedTemplateShift.shiftTypeId)
            |> applyRosterShiftAssignment plan.preparedAssignment
            |> createRecord
            |> void
    pure appliedVersion

persistCleanedTemplateVersion ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    PreparedApplication ->
    IO Int
persistCleanedTemplateVersion actor prepared
    | not (any (isJust . (.preparedAssignmentIssue)) prepared.preparedShiftPlans) =
        pure prepared.preparedSaved.savedTemplate.currentVersion
    | otherwise = do
        let template = prepared.preparedSaved.savedTemplate
        let sourceDesign = prepared.preparedSaved.savedDesign
        let nextVersion = template.currentVersion + 1
        nextDesign <-
            newRecord @RosterTemplateDesign
                |> set #rosterGroupId sourceDesign.rosterGroupId
                |> set #scale sourceDesign.scale
                |> set #draftOwnerUserId Nothing
                |> set #draftName Nothing
                |> set #templateId (Just (unpackId template.id))
                |> set #versionNumber (Just nextVersion)
                |> set #sourceTemplateId Nothing
                |> set #baseVersionNumber Nothing
                |> set #createdByUserId (unpackId (rosterTemplateActorUserId actor))
                |> createRecord
        nextDays <- forM prepared.preparedSaved.savedDays \sourceDay ->
            newRecord @RosterTemplateDay
                |> set #rosterTemplateDesignId (unpackId nextDesign.id)
                |> set #dayIndex sourceDay.dayIndex
                |> set #weekdayIndex sourceDay.weekdayIndex
                |> set #isClosed sourceDay.isClosed
                |> set #rowCount sourceDay.rowCount
                |> createRecord
        nextColumns <- forM prepared.preparedSaved.savedColumns \sourceColumn ->
            newRecord @RosterTemplateColumn
                |> set #rosterTemplateDesignId (unpackId nextDesign.id)
                |> set #name sourceColumn.name
                |> set #sortOrder sourceColumn.sortOrder
                |> createRecord
        let nextDayByIndex = Map.fromList [(day.dayIndex, day) | day <- nextDays]
        let sourceDayIndexById = Map.fromList [(unpackId day.id, day.dayIndex) | day <- prepared.preparedSaved.savedDays]
        let nextColumnBySort = Map.fromList [(column.sortOrder, column) | column <- nextColumns]
        let sourceColumnSortById = Map.fromList [(unpackId column.id, column.sortOrder) | column <- prepared.preparedSaved.savedColumns]
        let planByShiftId = Map.fromList [(unpackId plan.preparedTemplateShift.id, plan) | plan <- prepared.preparedShiftPlans]
        forM_ prepared.preparedSaved.savedShifts \sourceShift -> do
            let dayIndex = sourceDayIndexById Map.! sourceShift.rosterTemplateDayId
            let columnSort = sourceColumnSortById Map.! sourceShift.rosterTemplateColumnId
            let targetDay = nextDayByIndex Map.! dayIndex
            let targetColumn = nextColumnBySort Map.! columnSort
            let assignment = maybe OpenAssignment (.preparedAssignment) (Map.lookup (unpackId sourceShift.id) planByShiftId)
            newRecord @RosterTemplateShift
                |> set #rosterTemplateDesignId (unpackId nextDesign.id)
                |> set #rosterTemplateDayId (unpackId targetDay.id)
                |> set #rosterTemplateColumnId (unpackId targetColumn.id)
                |> set #rowIndex sourceShift.rowIndex
                |> set #startMinute sourceShift.startMinute
                |> set #endMinute sourceShift.endMinute
                |> set #shiftTypeId sourceShift.shiftTypeId
                |> applyTemplateShiftAssignment assignment
                |> createRecord
                |> void
        template |> set #currentVersion nextVersion |> updateRecord |> void
        pure nextVersion

applyTemplateShiftAssignment :: RosterShiftAssignment -> RosterTemplateShift -> RosterTemplateShift
applyTemplateShiftAssignment assignment shift = case assignment of
    StaffAssignment staffId ->
        shift
            |> set #assignmentState "staff"
            |> set #staffId (Just (unpackId staffId))
    OpenAssignment ->
        shift
            |> set #assignmentState "open"
            |> set #staffId Nothing

applyDayStates :: (?modelContext :: ModelContext) => PreparedApplication -> IO ()
applyDayStates prepared = do
    let templateDayByIndex = Map.fromList
            [ (fromMaybe day.dayIndex day.weekdayIndex, day)
            | day <- prepared.preparedSaved.savedDays
            ]
    forM_ prepared.preparedTargetDays \targetDay -> do
        let templateIndex = case prepared.preparedSaved.savedTemplate.scale of
                Day  -> 0
                Week -> weekdayIndexForDay targetDay.operationalDate
        case Map.lookup templateIndex templateDayByIndex of
            Nothing -> pure ()
            Just templateDay ->
                targetDay
                    |> set #isClosed templateDay.isClosed
                    |> set #rowCount templateDay.rowCount
                    |> updateRecord
                    |> void

ensureTargetLanes ::
    (?modelContext :: ModelContext) =>
    PreparedApplication ->
    IO [RosterLane]
ensureTargetLanes prepared = do
    let targetDayIds = map (unpackId . (.id)) prepared.preparedTargetDays
    existing <- if null targetDayIds then pure [] else query @RosterLane
        |> filterWhereIn (#rosterDayId, targetDayIds)
        |> filterWhere (#deletedAt, Nothing)
        |> orderByAsc #sortOrder
        |> fetch
    case prepared.preparedSaved.savedTemplate.scale of
        Week -> do
            now <- getCurrentTime
            forM_ existing \lane ->
                lane
                    |> set #deletedAt (Just now)
                    |> set #deleteReason (Just "roster_template_applied")
                    |> updateRecord
                    |> void
            concat <$> forM prepared.preparedTargetDays (\targetDay ->
                forM prepared.preparedSaved.savedColumns (createLane targetDay))
        Day -> do
            let targetDay = prepared.preparedFirstTargetDay
            let existingNames = Map.fromList [(Text.toCaseFold (Text.strip lane.name), lane) | lane <- existing]
            let missing = filter (\column -> Map.notMember (Text.toCaseFold (Text.strip column.name)) existingNames) prepared.preparedSaved.savedColumns
            created <- forM (zip missing [nextSortOrder existing ..]) \(column, sortOrder) ->
                createLaneAtSort targetDay column sortOrder
            pure (existing <> created)

createLane :: (?modelContext :: ModelContext) => RosterDay -> RosterTemplateColumn -> IO RosterLane
createLane rosterDay column = createLaneAtSort rosterDay column column.sortOrder

createLaneAtSort :: (?modelContext :: ModelContext) => RosterDay -> RosterTemplateColumn -> Int -> IO RosterLane
createLaneAtSort rosterDay column sortOrder =
    newRecord @RosterLane
        |> set #rosterDayId (unpackId rosterDay.id)
        |> set #name column.name
        |> set #sortOrder sortOrder
        |> createRecord

nextSortOrder :: [RosterLane] -> Int
nextSortOrder []    = 0
nextSortOrder lanes = maximum (map (.sortOrder) lanes) + 1

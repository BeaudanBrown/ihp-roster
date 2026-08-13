{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.RosterWeeks.TemplateApplication.Persistence
    ( applyPreparedApplication
    ) where

import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          applyRosterShiftAssignment)
import Application.RosterTemplates (RosterTemplateActor,
                                    remediateRosterTemplateAssignmentsInCurrentTransaction,
                                    rosterTemplateActorUserId,
                                    snapshotColumns, snapshotDays,
                                    snapshotTemplate)
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
    appliedVersion <- persistCleanedTemplateSnapshot actor prepared
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

persistCleanedTemplateSnapshot ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    PreparedApplication ->
    IO Int
persistCleanedTemplateSnapshot actor prepared
    | null invalidShiftIds = pure 0
    | otherwise = do
        remediated <- remediateRosterTemplateAssignmentsInCurrentTransaction actor prepared.preparedSaved invalidShiftIds
        case remediated of
            Left templateError -> error ("validated roster template remediation failed: " <> show templateError)
            Right _ -> pure 0
  where
    invalidShiftIds =
        [ plan.preparedTemplateShift.id
        | plan <- prepared.preparedShiftPlans
        , isJust plan.preparedAssignmentIssue
        ]

applyDayStates :: (?modelContext :: ModelContext) => PreparedApplication -> IO ()
applyDayStates prepared = do
    let templateDayByIndex = Map.fromList
            [ (fromMaybe day.dayIndex day.weekdayIndex, day)
            | day <- prepared.preparedSaved.snapshotDays
            ]
    forM_ prepared.preparedTargetDays \targetDay -> do
        let templateIndex = case prepared.preparedSaved.snapshotTemplate.scale of
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
    case prepared.preparedSaved.snapshotTemplate.scale of
        Week -> do
            now <- getCurrentTime
            forM_ existing \lane ->
                lane
                    |> set #deletedAt (Just now)
                    |> set #deleteReason (Just "roster_template_applied")
                    |> updateRecord
                    |> void
            concat <$> forM prepared.preparedTargetDays (\targetDay ->
                forM prepared.preparedSaved.snapshotColumns (createLane targetDay))
        Day -> do
            let targetDay = prepared.preparedFirstTargetDay
            let existingNames = Map.fromList [(Text.toCaseFold (Text.strip lane.name), lane) | lane <- existing]
            let missing = filter (\column -> Map.notMember (Text.toCaseFold (Text.strip column.name)) existingNames) prepared.preparedSaved.snapshotColumns
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

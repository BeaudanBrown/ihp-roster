{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.RosterWeeks.TemplateApplication.Persistence
    ( applyPreparedApplication
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          applyRosterShiftAssignment)
import Application.RosterTemplates (RosterTemplateActor,
                                    replaceRosterTemplateContentInCurrentTransaction,
                                    rosterTemplateActorUserId, snapshotColumns,
                                    snapshotDays, snapshotTemplate)
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
    IO Bool
applyPreparedApplication actor prepared = do
    now <- getCurrentTime
    forM_ prepared.preparedExistingSlots \slot ->
        slot
            |> set #deletedAt (Just now)
            |> set #deletedByUserId (Just (unpackId (rosterTemplateActorUserId actor)))
            |> set #deleteReason (Just "roster_template_applied")
            |> updateRecord
            |> void
    templateChanged <- persistCleanedTemplateSnapshot actor prepared
    applyDayStates prepared
    lanes <- ensureTargetLanes prepared
    let laneByDayAndName = Map.fromList [((lane.rosterDayId, Text.toCaseFold (Text.strip lane.name)), lane) | lane <- lanes]
    forM_ prepared.preparedShiftPlans \plan -> do
        let lane = fromMaybe (externalRuntimeInvariantFailure PersistedRuntimeInvariant "prepared roster template lane missing")
                (Map.lookup (unpackId plan.preparedTargetDay.id, Text.toCaseFold (Text.strip plan.preparedTemplateColumn.name)) laneByDayAndName)
        newRecord @RosterSlot
            |> set #rosterDayId (unpackId plan.preparedTargetDay.id)
            |> set #rosterLaneId (unpackId lane.id)
            |> set #slotSortOrder lane.sortOrder
            |> set #rowIndex plan.preparedTemplateShift.rowIndex
            |> set #startsAt (Just plan.preparedStartsAt)
            |> set #endsAt (Just plan.preparedEndsAt)
            |> set #timezone melbourneTimeZoneName
            |> set #shiftTypeId (Just (unpackId plan.preparedShiftTypeId))
            |> applyRosterShiftAssignment plan.preparedAssignment
            |> createRecord
            |> void
    pure templateChanged

persistCleanedTemplateSnapshot ::
    (?modelContext :: ModelContext) =>
    RosterTemplateActor ->
    PreparedApplication ->
    IO Bool
persistCleanedTemplateSnapshot actor prepared = case prepared.preparedCleanedTemplateContent of
    Nothing -> pure False
    Just cleanedContent -> do
        remediated <- replaceRosterTemplateContentInCurrentTransaction actor prepared.preparedSaved.snapshotTemplate.id cleanedContent
        case remediated of
            Left _ -> externalRuntimeInvariantFailure PersistedRuntimeInvariant "validated roster template remediation failed"
            Right _ -> pure True

applyDayStates :: (?modelContext :: ModelContext) => PreparedApplication -> IO ()
applyDayStates prepared = do
    let templateDayByWeekday = Map.fromList
            [ (fromMaybe (externalRuntimeInvariantFailure PersistedRuntimeInvariant "validated Week snapshot lost weekday identity") day.weekdayIndex, day)
            | day <- prepared.preparedSaved.snapshotDays
            ]
    forM_ prepared.preparedTargetDays \targetDay -> do
        let targetWeekday = weekdayIndexForDay targetDay.operationalDate
        case Map.lookup targetWeekday templateDayByWeekday of
            Nothing -> pure ()
            Just templateDay ->
                targetDay
                    |> set #publicationState Draft
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
    now <- getCurrentTime
    forM_ existing \lane ->
        lane
            |> set #deletedAt (Just now)
            |> set #deleteReason (Just "roster_template_applied")
            |> updateRecord
            |> void
    concat <$> forM prepared.preparedTargetDays (\targetDay ->
        forM prepared.preparedSaved.snapshotColumns (createLane targetDay))

createLane :: (?modelContext :: ModelContext) => RosterDay -> RosterTemplateColumn -> IO RosterLane
createLane rosterDay column = createLaneAtSort rosterDay column column.sortOrder

createLaneAtSort :: (?modelContext :: ModelContext) => RosterDay -> RosterTemplateColumn -> Int -> IO RosterLane
createLaneAtSort rosterDay column sortOrder =
    newRecord @RosterLane
        |> set #rosterDayId (unpackId rosterDay.id)
        |> set #name column.name
        |> set #sortOrder sortOrder
        |> createRecord

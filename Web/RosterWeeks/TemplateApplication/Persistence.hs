{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.RosterWeeks.TemplateApplication.Persistence
    ( applyPreparedApplication
    ) where

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
    definitions <- ensureTargetDefinitions prepared
    let definitionByName = Map.fromList [(Text.toCaseFold (Text.strip definition.name), definition) | definition <- definitions]
    forM_ prepared.preparedShiftPlans \plan -> do
        let definition = definitionByName Map.! Text.toCaseFold (Text.strip plan.preparedTemplateColumn.name)
        newRecord @RosterSlot
            |> set #rosterDayId (unpackId plan.preparedTargetDay.id)
            |> set #rosterWeekSlotDefinitionId (Just (unpackId definition.id))
            |> set #slotSortOrder definition.sortOrder
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
    let templateDayByIndex = Map.fromList [(day.dayIndex, day) | day <- prepared.preparedSaved.savedDays]
    forM_ prepared.preparedTargetDays \targetDay -> do
        let templateIndex = case prepared.preparedSaved.savedTemplate.scale of
                Day  -> 0
                Week -> targetDay.dayOffset
        case Map.lookup templateIndex templateDayByIndex of
            Nothing -> pure ()
            Just templateDay ->
                targetDay
                    |> set #isClosed templateDay.isClosed
                    |> set #rowCount templateDay.rowCount
                    |> updateRecord
                    |> void

ensureTargetDefinitions ::
    (?modelContext :: ModelContext) =>
    PreparedApplication ->
    IO [RosterWeekSlotDefinition]
ensureTargetDefinitions prepared = do
    existing <- query @RosterWeekSlotDefinition
        |> filterWhere (#rosterWeekId, unpackId prepared.preparedTargetWeek.id)
        |> filterWhere (#deletedAt, Nothing)
        |> orderByAsc #sortOrder
        |> fetch
    case prepared.preparedSaved.savedTemplate.scale of
        Week -> do
            now <- getCurrentTime
            forM_ existing \definition ->
                definition
                    |> set #deletedAt (Just now)
                    |> set #deleteReason (Just "roster_template_applied")
                    |> updateRecord
                    |> void
            forM prepared.preparedSaved.savedColumns \column ->
                createDefinition prepared.preparedTargetWeek column.name column.sortOrder
        Day -> do
            let existingNames = Map.fromList [(Text.toCaseFold (Text.strip definition.name), definition) | definition <- existing]
            let missing = filter (\column -> Map.notMember (Text.toCaseFold (Text.strip column.name)) existingNames) prepared.preparedSaved.savedColumns
            created <- forM (zip missing [nextSortOrder existing ..]) \(column, sortOrder) ->
                createDefinition prepared.preparedTargetWeek column.name sortOrder
            pure (existing <> created)

createDefinition :: (?modelContext :: ModelContext) => RosterWeek -> Text -> Int -> IO RosterWeekSlotDefinition
createDefinition rosterWeek name sortOrder =
    newRecord @RosterWeekSlotDefinition
        |> set #rosterWeekId (unpackId rosterWeek.id)
        |> set #name name
        |> set #sortOrder sortOrder
        |> createRecord

nextSortOrder :: [RosterWeekSlotDefinition] -> Int
nextSortOrder []          = 0
nextSortOrder definitions = maximum (map (.sortOrder) definitions) + 1

module Web.RosterWeeks.Mutations
    ( RosterSlotMutationResult (..)
    , addRosterDayRowMutation
    , appendRosterWeekSlotDefinitionMutation
    , copyRosterWeekFromSourceMutation
    , ensureRosterWeekExistsMutation
    , moveRosterSlotMutation
    , removeRosterDayRowMutation
    , renameRosterWeekSlotDefinitionMutation
    , repackRosterWeekMutation
    , rosterDayTouchedResources
    , rosterSlotTouchedResources
    , rosterWeekTouchedResources
    , saveRosterSlotMutation
    , toggleRosterDayClosedMutation
    , toggleRosterWeekLiveStatusMutation
    , updateRosterSlotMutation
    , deleteRosterSlotMutation
    , removeRosterWeekSlotDefinitionMutation
    ) where

import Application.Helper.SurfaceResource
import Application.RosterTimesheets.Automation (cancelPendingRosterTimesheetCreationJobsForWeek,
                                                enqueueRosterTimesheetCreationJobsForWeek,
                                                rosterSlotHasGeneratedTimesheet)
import Data.Coerce (coerce)
import Data.List (nub)
import Data.Time (getCurrentTime)
import Data.UUID (UUID)
import Web.Controller.Prelude
import Web.RosterWeeks.Service
import Web.SurfaceInvalidation (invalidateTouchedResources)

data RosterSlotMutationResult = RosterSlotMutationResult
    { rosterSlotMutationSlot                              :: !(Maybe RosterSlot)
    , rosterSlotMutationPreviousStaffId                   :: !(Maybe UUID)
    , rosterSlotMutationShouldWarnSourceTimesheetUnchanged :: !Bool
    }

ensureRosterWeekExistsMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (LiveMutationResult (RosterWeek, Bool))
ensureRosterWeekExistsMutation rosterGroupId weekOffset = do
    result@(_, wasCreated) <- ensureRosterWeekExists rosterGroupId weekOffset
    let mutationResult = liveMutationResult result (rosterWeekTouchedResources rosterGroupId weekOffset)
    if wasCreated
        then invalidateTouchedResources "roster.week.ensure" mutationResult
        else pure mutationResult

copyRosterWeekFromSourceMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> Int -> IO (LiveMutationResult RosterWeek)
copyRosterWeekFromSourceMutation rosterGroupId sourceWeek targetWeekOffset = do
    targetWeek <- withTransaction do
        existingTarget <- query @RosterWeek
            |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
            |> filterWhere (#weekOffset, targetWeekOffset)
            |> fetchOneOrNothing
        case existingTarget of
            Just targetWeek -> replaceRosterWeekFromSource sourceWeek targetWeek
            Nothing         -> copyRosterWeek sourceWeek targetWeekOffset
    invalidateTouchedResources "roster.week.copy" (liveMutationResult targetWeek (rosterWeekTouchedResources rosterGroupId targetWeekOffset))

toggleRosterWeekLiveStatusMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> Bool -> IO (LiveMutationResult (RosterWeek, Int))
toggleRosterWeekLiveStatusMutation rosterGroupId rosterWeek nextLiveStatus = do
    (updatedRosterWeek, queuedTimesheetJobs) <-
        if nextLiveStatus
            then do
                updatedRosterWeek <- rosterWeek
                    |> set #isLive True
                    |> updateRecord
                queuedTimesheetJobs <- enqueueRosterTimesheetCreationJobsForWeek (Just currentUser.id) updatedRosterWeek
                pure (updatedRosterWeek, queuedTimesheetJobs)
            else do
                updatedRosterWeek <- withTransaction do
                    updatedRosterWeek <- rosterWeek
                        |> set #isLive False
                        |> updateRecord
                    _cancelledJobCount <- cancelPendingRosterTimesheetCreationJobsForWeek updatedRosterWeek
                    pure updatedRosterWeek
                pure (updatedRosterWeek, [])
    invalidateTouchedResources "roster.week.live_status" (liveMutationResult (updatedRosterWeek, length queuedTimesheetJobs) (rosterWeekTouchedResources rosterGroupId rosterWeek.weekOffset))

appendRosterWeekSlotDefinitionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> Text -> IO (LiveMutationResult RosterWeekSlotDefinition)
appendRosterWeekSlotDefinitionMutation rosterGroupId rosterWeek slotName = do
    slotDefinition <- withTransaction (appendRosterWeekSlotDefinition rosterWeek slotName)
    invalidateTouchedResources "roster.slot_definition.append" (liveMutationResult slotDefinition (rosterWeekTouchedResources rosterGroupId rosterWeek.weekOffset))

renameRosterWeekSlotDefinitionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterWeekSlotDefinition -> Text -> IO (LiveMutationResult RosterWeekSlotDefinition)
renameRosterWeekSlotDefinitionMutation rosterGroupId rosterWeek slotDefinition slotName = do
    updatedSlotDefinition <- slotDefinition
        |> set #name slotName
        |> updateRecord
    invalidateTouchedResources "roster.slot_definition.rename" (liveMutationResult updatedSlotDefinition (rosterWeekTouchedResources rosterGroupId rosterWeek.weekOffset))

removeRosterWeekSlotDefinitionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterWeekSlotDefinition -> IO (LiveMutationResult ())
removeRosterWeekSlotDefinitionMutation rosterGroupId rosterWeek slotDefinition = do
    withTransaction (deleteRosterWeekSlotDefinition slotDefinition)
    invalidateTouchedResources "roster.slot_definition.remove" (liveMutationResult () (rosterWeekTouchedResources rosterGroupId rosterWeek.weekOffset))

repackRosterWeekMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWeek -> IO (LiveMutationResult ())
repackRosterWeekMutation rosterWeek = do
    let rosterGroupId = coerce rosterWeek.rosterGroupId
    withTransaction (repackRosterWeekDays rosterWeek)
    invalidateTouchedResources "roster.week.repack" (liveMutationResult () (rosterWeekTouchedResources rosterGroupId rosterWeek.weekOffset))

toggleRosterDayClosedMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> Bool -> Int -> IO (LiveMutationResult RosterDay)
toggleRosterDayClosedMutation rosterGroupId rosterWeek rosterDay nextClosedState minimumRows = do
    when nextClosedState do
        ensureRosterDayHasMinimumRows rosterDay rosterGroupId minimumRows
    updatedDay <- rosterDay |> set #isClosed nextClosedState |> updateRecord
    invalidateTouchedResources "roster.day.closed" (liveMutationResult updatedDay (rosterDayTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay))

addRosterDayRowMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> IO (LiveMutationResult RosterDay)
addRosterDayRowMutation rosterGroupId rosterWeek rosterDay = do
    updatedDay <- rosterDay
        |> set #rowCount (rosterDay.rowCount + 1)
        |> updateRecord
    invalidateTouchedResources "roster.day.row_add" (liveMutationResult updatedDay (rosterDayTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay))

removeRosterDayRowMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> [RosterWeekSlotDefinition] -> IO (LiveMutationResult ())
removeRosterDayRowMutation rosterGroupId rosterWeek rosterDay activeDefinitions = do
    withTransaction (removeRosterRowWithPacking rosterDay activeDefinitions)
    invalidateTouchedResources "roster.day.row_remove" (liveMutationResult () (rosterDayTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay))

saveRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> Maybe RosterSlot -> RosterSlot -> IO (LiveMutationResult RosterSlotMutationResult)
saveRosterSlotMutation rosterGroupId rosterWeek rosterDay existingSlot newSlot = do
    when (newSlot.rowIndex >= rosterDay.rowCount) do
        _ <- rosterDay
            |> set #rowCount (newSlot.rowIndex + 1)
            |> updateRecord
        pure ()
    persistedSlot <-
        case existingSlot of
            Just _  -> updateRecord newSlot
            Nothing -> createRecord newSlot
    invalidateTouchedResources "roster.slot.save" (liveMutationResult (RosterSlotMutationResult (Just persistedSlot) Nothing False) (rosterSlotTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay (Just persistedSlot)))

moveRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> RosterDay -> RosterSlot -> RosterSlot -> IO (LiveMutationResult RosterSlotMutationResult)
moveRosterSlotMutation rosterGroupId rosterWeek sourceRosterDay targetRosterDay originalSlot updatedSlot = do
    let previousStaffId = originalSlot.staffId
    sourceTimesheetExists <- rosterSlotHasGeneratedTimesheet originalSlot
    when (updatedSlot.rowIndex >= targetRosterDay.rowCount) do
        _ <- targetRosterDay
            |> set #rowCount (updatedSlot.rowIndex + 1)
            |> updateRecord
        pure ()
    persistedSlot <- updateRecord updatedSlot
    let shouldWarnSourceTimesheetUnchanged =
            sourceTimesheetExists && rosterSlotTimesheetSourceChanged originalSlot updatedSlot
    invalidateTouchedResources "roster.slot.move" $
        liveMutationResult
            RosterSlotMutationResult
                { rosterSlotMutationSlot = Just persistedSlot
                , rosterSlotMutationPreviousStaffId = previousStaffId
                , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged
                }
            (nub (rosterDayTouchedResources rosterGroupId rosterWeek.weekOffset sourceRosterDay <> rosterSlotTouchedResources rosterGroupId rosterWeek.weekOffset targetRosterDay (Just persistedSlot)))

updateRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> RosterSlot -> RosterSlot -> IO (LiveMutationResult RosterSlotMutationResult)
updateRosterSlotMutation rosterGroupId rosterWeek rosterDay originalSlot updatedSlot = do
    let previousStaffId = originalSlot.staffId
    sourceTimesheetExists <- rosterSlotHasGeneratedTimesheet originalSlot
    persistedSlot <- updateRecord updatedSlot
    let shouldWarnSourceTimesheetUnchanged =
            sourceTimesheetExists && rosterSlotTimesheetSourceChanged originalSlot updatedSlot
    invalidateTouchedResources "roster.slot.update" $
        liveMutationResult
            RosterSlotMutationResult
                { rosterSlotMutationSlot = Just persistedSlot
                , rosterSlotMutationPreviousStaffId = previousStaffId
                , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged
                }
            (rosterSlotTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay (Just persistedSlot))


deleteRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> RosterSlot -> IO (LiveMutationResult RosterSlotMutationResult)
deleteRosterSlotMutation rosterGroupId rosterWeek rosterDay rosterSlot = do
    let previousStaffId = rosterSlot.staffId
    now <- getCurrentTime
    deletedSlot <- rosterSlot
        |> set #deletedAt (Just now)
        |> set #deletedByUserId (Just (unpackId currentUser.id))
        |> set #deleteReason (Just "roster_slot_deleted_from_dialog")
        |> updateRecord
    invalidateTouchedResources "roster.slot.delete" $
        liveMutationResult
            RosterSlotMutationResult
                { rosterSlotMutationSlot = Nothing
                , rosterSlotMutationPreviousStaffId = previousStaffId
                , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = False
                }
            (rosterSlotTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay (Just deletedSlot))

rosterWeekTouchedResources :: Id RosterGroup -> Int -> [SurfaceResourceValue]
rosterWeekTouchedResources rosterGroupId weekOffset =
    [ rosterWeekResource (unpackId rosterGroupId) weekOffset ]

rosterDayTouchedResources :: Id RosterGroup -> Int -> RosterDay -> [SurfaceResourceValue]
rosterDayTouchedResources rosterGroupId weekOffset rosterDay =
    rosterWeekTouchedResources rosterGroupId weekOffset
        <> [rosterDayResource (unpackId rosterDay.id)]

rosterSlotTouchedResources :: Id RosterGroup -> Int -> RosterDay -> Maybe RosterSlot -> [SurfaceResourceValue]
rosterSlotTouchedResources rosterGroupId weekOffset rosterDay maybeSlot =
    rosterDayTouchedResources rosterGroupId weekOffset rosterDay

rosterSlotTimesheetSourceChanged :: RosterSlot -> RosterSlot -> Bool
rosterSlotTimesheetSourceChanged previous next =
    previous.staffId /= next.staffId
        || previous.startTime /= next.startTime
        || previous.endTime /= next.endTime
        || previous.shiftTypeId /= next.shiftTypeId

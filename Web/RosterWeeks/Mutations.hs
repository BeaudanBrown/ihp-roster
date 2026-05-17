module Web.RosterWeeks.Mutations
    ( RosterSlotMutationResult (..)
    , addRosterDayRowMutation
    , appendRosterWeekSlotDefinitionMutation
    , copyRosterWeekFromSourceMutation
    , ensureRosterWeekExistsMutation
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
    , removeRosterWeekSlotDefinitionMutation
    ) where

import Application.Helper.LiveResource
import Application.RosterTimesheets.Automation (enqueueRosterTimesheetCreationJobsForWeek,
                                                rosterSlotHasGeneratedTimesheet)
import Data.Coerce (coerce)
import Data.Time (getCurrentTime)
import Data.UUID (UUID)
import Web.Controller.Prelude
import Web.RosterWeeks.LiveUpdates (refreshRosterContent,
                                    refreshRosterContentAndStaffPanel)
import Web.RosterWeeks.Service

data RosterSlotMutationResult = RosterSlotMutationResult
    { rosterSlotMutationSlot                              :: !(Maybe RosterSlot)
    , rosterSlotMutationPreviousStaffId                   :: !(Maybe UUID)
    , rosterSlotMutationShouldWarnSourceTimesheetUnchanged :: !Bool
    }

ensureRosterWeekExistsMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (LiveMutationResult (RosterWeek, Bool))
ensureRosterWeekExistsMutation rosterGroupId weekOffset = do
    result@(_, wasCreated) <- ensureRosterWeekExists rosterGroupId weekOffset
    when wasCreated do
        refreshRosterContent rosterGroupId weekOffset
    pure (liveMutationResult result (rosterWeekTouchedResources rosterGroupId weekOffset))

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
    refreshRosterContent rosterGroupId targetWeekOffset
    pure (liveMutationResult targetWeek (rosterWeekTouchedResources rosterGroupId targetWeekOffset))

toggleRosterWeekLiveStatusMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> Bool -> IO (LiveMutationResult (RosterWeek, Int))
toggleRosterWeekLiveStatusMutation rosterGroupId rosterWeek nextLiveStatus = do
    updatedRosterWeek <- rosterWeek
        |> set #isLive nextLiveStatus
        |> updateRecord
    queuedTimesheetJobs <-
        if nextLiveStatus
            then enqueueRosterTimesheetCreationJobsForWeek (Just currentUser.id) updatedRosterWeek
            else pure []
    refreshRosterContent rosterGroupId rosterWeek.weekOffset
    pure (liveMutationResult (updatedRosterWeek, length queuedTimesheetJobs) (rosterWeekTouchedResources rosterGroupId rosterWeek.weekOffset))

appendRosterWeekSlotDefinitionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> Text -> IO (LiveMutationResult RosterWeekSlotDefinition)
appendRosterWeekSlotDefinitionMutation rosterGroupId rosterWeek slotName = do
    slotDefinition <- withTransaction (appendRosterWeekSlotDefinition rosterWeek slotName)
    refreshRosterContentAndStaffPanel rosterGroupId rosterWeek.weekOffset
    pure (liveMutationResult slotDefinition (rosterWeekTouchedResources rosterGroupId rosterWeek.weekOffset))

renameRosterWeekSlotDefinitionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterWeekSlotDefinition -> Text -> IO (LiveMutationResult RosterWeekSlotDefinition)
renameRosterWeekSlotDefinitionMutation rosterGroupId rosterWeek slotDefinition slotName = do
    updatedSlotDefinition <- slotDefinition
        |> set #name slotName
        |> updateRecord
    refreshRosterContent rosterGroupId rosterWeek.weekOffset
    pure (liveMutationResult updatedSlotDefinition (rosterWeekTouchedResources rosterGroupId rosterWeek.weekOffset))

removeRosterWeekSlotDefinitionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterWeekSlotDefinition -> IO (LiveMutationResult ())
removeRosterWeekSlotDefinitionMutation rosterGroupId rosterWeek slotDefinition = do
    withTransaction (deleteRosterWeekSlotDefinition slotDefinition)
    refreshRosterContentAndStaffPanel rosterGroupId rosterWeek.weekOffset
    pure (liveMutationResult () (rosterWeekTouchedResources rosterGroupId rosterWeek.weekOffset))

repackRosterWeekMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWeek -> IO (LiveMutationResult ())
repackRosterWeekMutation rosterWeek = do
    let rosterGroupId = coerce rosterWeek.rosterGroupId
    withTransaction (repackRosterWeekDays rosterWeek)
    refreshRosterContentAndStaffPanel rosterGroupId rosterWeek.weekOffset
    pure (liveMutationResult () (rosterWeekTouchedResources rosterGroupId rosterWeek.weekOffset))

toggleRosterDayClosedMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> Bool -> Int -> IO (LiveMutationResult RosterDay)
toggleRosterDayClosedMutation rosterGroupId rosterWeek rosterDay nextClosedState minimumRows = do
    when nextClosedState do
        ensureRosterDayHasMinimumRows rosterDay rosterGroupId minimumRows
    updatedDay <- rosterDay |> set #isClosed nextClosedState |> updateRecord
    refreshRosterContentAndStaffPanel rosterGroupId rosterWeek.weekOffset
    pure (liveMutationResult updatedDay (rosterDayTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay))

addRosterDayRowMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> IO (LiveMutationResult RosterDay)
addRosterDayRowMutation rosterGroupId rosterWeek rosterDay = do
    updatedDay <- rosterDay
        |> set #rowCount (rosterDay.rowCount + 1)
        |> updateRecord
    refreshRosterContentAndStaffPanel rosterGroupId rosterWeek.weekOffset
    pure (liveMutationResult updatedDay (rosterDayTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay))

removeRosterDayRowMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> [RosterWeekSlotDefinition] -> IO (LiveMutationResult ())
removeRosterDayRowMutation rosterGroupId rosterWeek rosterDay activeDefinitions = do
    withTransaction (removeRosterRowWithPacking rosterDay activeDefinitions)
    refreshRosterContentAndStaffPanel rosterGroupId rosterWeek.weekOffset
    pure (liveMutationResult () (rosterDayTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay))

saveRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> Maybe RosterSlot -> RosterSlot -> IO (LiveMutationResult RosterSlotMutationResult)
saveRosterSlotMutation rosterGroupId rosterWeek rosterDay existingSlot newSlot = do
    when (newSlot.rowIndex >= rosterDay.rowCount) do
        _ <- rosterDay
            |> set #rowCount (newSlot.rowIndex + 1)
            |> updateRecord
        pure ()
    persistedSlot <-
        case (existingSlot, rosterSlotHasData newSlot) of
            (Just _, True) ->
                Just <$> updateRecord newSlot
            (Just _, False) -> do
                now <- getCurrentTime
                _ <- newSlot
                    |> set #deletedAt (Just now)
                    |> set #deletedByUserId (Just (unpackId currentUser.id))
                    |> set #deleteReason (Just "roster_slot_cleared")
                    |> updateRecord
                pure Nothing
            (Nothing, True) ->
                Just <$> createRecord newSlot
            (Nothing, False) ->
                pure Nothing
    pure (liveMutationResult (RosterSlotMutationResult persistedSlot Nothing False) (rosterSlotTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay persistedSlot))

updateRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> RosterSlot -> RosterSlot -> IO (LiveMutationResult RosterSlotMutationResult)
updateRosterSlotMutation rosterGroupId rosterWeek rosterDay originalSlot updatedSlot = do
    let previousStaffId = originalSlot.staffId
    sourceTimesheetExists <- rosterSlotHasGeneratedTimesheet originalSlot
    persistedSlot <-
        if rosterSlotHasData updatedSlot
            then Just <$> updateRecord updatedSlot
            else do
                now <- getCurrentTime
                _ <- updatedSlot
                    |> set #deletedAt (Just now)
                    |> set #deletedByUserId (Just (unpackId currentUser.id))
                    |> set #deleteReason (Just "roster_slot_cleared")
                    |> updateRecord
                pure Nothing
    let shouldWarnSourceTimesheetUnchanged =
            sourceTimesheetExists && rosterSlotTimesheetSourceChanged originalSlot updatedSlot
    pure
        ( liveMutationResult
            RosterSlotMutationResult
                { rosterSlotMutationSlot = persistedSlot
                , rosterSlotMutationPreviousStaffId = previousStaffId
                , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged
                }
            (rosterSlotTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay persistedSlot)
        )

rosterWeekTouchedResources :: Id RosterGroup -> Int -> [LiveResource]
rosterWeekTouchedResources rosterGroupId weekOffset =
    [ RosterWeekResource (unpackId rosterGroupId) weekOffset ]

rosterDayTouchedResources :: Id RosterGroup -> Int -> RosterDay -> [LiveResource]
rosterDayTouchedResources rosterGroupId weekOffset rosterDay =
    rosterWeekTouchedResources rosterGroupId weekOffset
        <> [RosterDayResource (unpackId rosterDay.id)]

rosterSlotTouchedResources :: Id RosterGroup -> Int -> RosterDay -> Maybe RosterSlot -> [LiveResource]
rosterSlotTouchedResources rosterGroupId weekOffset rosterDay maybeSlot =
    rosterDayTouchedResources rosterGroupId weekOffset rosterDay
        <> maybe [] (\slot -> [RosterSlotResource (unpackId slot.id)]) maybeSlot

rosterSlotTimesheetSourceChanged :: RosterSlot -> RosterSlot -> Bool
rosterSlotTimesheetSourceChanged previous next =
    previous.staffId /= next.staffId
        || previous.startTime /= next.startTime
        || previous.endTime /= next.endTime
        || previous.shiftTypeId /= next.shiftTypeId

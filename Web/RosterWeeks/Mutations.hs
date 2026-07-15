module Web.RosterWeeks.Mutations
    ( RosterSlotMutationResult (..)
    , addRosterDayRowMutation
    , appendRosterWeekSlotDefinitionMutation
    , copyRosterWeekFromSourceMutation
    , ensureRosterWeekExistsMutation
    , moveRosterSlotMutation
    , removeRosterDayRowMutation
    , repackRosterWeekMutation
    , rosterDayTouchedResources
    , rosterSlotMutationTouchedResources
    , rosterSlotTouchedResources
    , rosterWeekLiveStatusTouchedResources
    , rosterWeekTouchedResources
    , saveRosterSlotMutation
    , toggleRosterDayClosedMutation
    , toggleRosterWeekLiveStatusMutation
    , updateRosterSlotMutation
    , deleteRosterSlotMutation
    , removeRosterWeekSlotDefinitionMutation
    ) where

import Application.Helper.FrontendContract.Surface.Roster.Resource
import Application.Helper.FrontendContract.Surface.Timesheets.Resource
import Application.Helper.SurfaceResource
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

toggleRosterWeekLiveStatusMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> Bool -> IO (LiveMutationResult RosterWeek)
toggleRosterWeekLiveStatusMutation rosterGroupId rosterWeek nextLiveStatus = do
    updatedRosterWeek <-
        rosterWeek
            |> set #isLive nextLiveStatus
            |> updateRecord
    invalidateTouchedResources
        "roster.week.live_status"
        ( liveMutationResult
            updatedRosterWeek
            (rosterWeekLiveStatusTouchedResources rosterGroupId rosterWeek)
        )

appendRosterWeekSlotDefinitionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> Text -> IO (LiveMutationResult RosterWeekSlotDefinition)
appendRosterWeekSlotDefinitionMutation rosterGroupId rosterWeek slotName = do
    slotDefinition <- withTransaction (appendRosterWeekSlotDefinition rosterWeek slotName)
    invalidateTouchedResources "roster.slot_definition.append" (liveMutationResult slotDefinition (rosterWeekTouchedResources rosterGroupId rosterWeek.weekOffset))

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
    invalidateTouchedResources "roster.slot.save" (liveMutationResult (RosterSlotMutationResult (Just persistedSlot) Nothing False) (rosterSlotMutationTouchedResources rosterGroupId rosterWeek rosterDay (Just persistedSlot)))

moveRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> RosterDay -> RosterSlot -> RosterSlot -> IO (LiveMutationResult RosterSlotMutationResult)
moveRosterSlotMutation rosterGroupId rosterWeek sourceRosterDay targetRosterDay originalSlot updatedSlot = do
    let previousStaffId = originalSlot.staffId
    when (updatedSlot.rowIndex >= targetRosterDay.rowCount) do
        _ <- targetRosterDay
            |> set #rowCount (updatedSlot.rowIndex + 1)
            |> updateRecord
        pure ()
    persistedSlot <- updateRecord updatedSlot
    shouldWarnSourceTimesheetUnchanged <- rosterSlotTimesheetSourceChangeRequiresWarning originalSlot updatedSlot
    invalidateTouchedResources "roster.slot.move" $
        liveMutationResult
            RosterSlotMutationResult
                { rosterSlotMutationSlot = Just persistedSlot
                , rosterSlotMutationPreviousStaffId = previousStaffId
                , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged
                }
            (nub (rosterDayTouchedResources rosterGroupId rosterWeek.weekOffset sourceRosterDay <> rosterSlotMutationTouchedResources rosterGroupId rosterWeek targetRosterDay (Just persistedSlot)))

updateRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> RosterSlot -> RosterSlot -> IO (LiveMutationResult RosterSlotMutationResult)
updateRosterSlotMutation rosterGroupId rosterWeek rosterDay originalSlot updatedSlot = do
    let previousStaffId = originalSlot.staffId
    persistedSlot <- updateRecord updatedSlot
    shouldWarnSourceTimesheetUnchanged <- rosterSlotTimesheetSourceChangeRequiresWarning originalSlot updatedSlot
    invalidateTouchedResources "roster.slot.update" $
        liveMutationResult
            RosterSlotMutationResult
                { rosterSlotMutationSlot = Just persistedSlot
                , rosterSlotMutationPreviousStaffId = previousStaffId
                , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged
                }
            (rosterSlotMutationTouchedResources rosterGroupId rosterWeek rosterDay (Just persistedSlot))


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
            (rosterSlotMutationTouchedResources rosterGroupId rosterWeek rosterDay (Just deletedSlot))

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

rosterWeekLiveStatusTouchedResources :: Id RosterGroup -> RosterWeek -> [SurfaceResourceValue]
rosterWeekLiveStatusTouchedResources rosterGroupId rosterWeek =
    rosterWeekTouchedResources rosterGroupId rosterWeek.weekOffset
        <> timesheetWeekTouchedResources rosterWeek

rosterSlotMutationTouchedResources :: Id RosterGroup -> RosterWeek -> RosterDay -> Maybe RosterSlot -> [SurfaceResourceValue]
rosterSlotMutationTouchedResources rosterGroupId rosterWeek rosterDay maybeSlot =
    rosterSlotTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay maybeSlot
        <> timesheetWeekTouchedResources rosterWeek

timesheetWeekTouchedResources :: RosterWeek -> [SurfaceResourceValue]
timesheetWeekTouchedResources rosterWeek =
    [timesheetWeekResource rosterWeek.venueId rosterWeek.weekOffset]

rosterSlotTimesheetSourceChangeRequiresWarning :: (?modelContext :: ModelContext) => RosterSlot -> RosterSlot -> IO Bool
rosterSlotTimesheetSourceChangeRequiresWarning previous next
    | rosterSlotTimesheetSourceChanged previous next = rosterSlotHasGeneratedTimesheet previous
    | otherwise = pure False
  where
    rosterSlotTimesheetSourceChanged left right =
        left.staffId /= right.staffId
            || left.startTime /= right.startTime
            || left.endTime /= right.endTime
            || left.shiftTypeId /= right.shiftTypeId

rosterSlotHasGeneratedTimesheet :: (?modelContext :: ModelContext) => RosterSlot -> IO Bool
rosterSlotHasGeneratedTimesheet rosterSlot =
    query @TimesheetEntry
        |> filterWhere (#sourceRosterSlotId, Just (unpackId rosterSlot.id))
        |> filterWhere (#deletedAt, Nothing)
        |> fetchExists

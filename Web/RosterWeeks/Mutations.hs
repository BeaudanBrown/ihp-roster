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
    , rosterSlotsStructureTouchedResources
    , rosterWeekLiveStatusTouchedResources
    , rosterWeekStructuralTouchedResources
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
import Application.Staff.Mutations (withStaffOperationalLocks)
import Application.VenueTime.Model (BoundaryModelError,
                                    ShiftCopyOccurrenceSelections)
import Data.Coerce (coerce)
import Data.List (nub)
import Data.Time (getCurrentTime)
import Data.Traversable (traverse)
import Data.UUID (UUID)
import qualified Database.PostgreSQL.Simple as PG
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
    let mutationResult = liveMutationResult result (rosterWeekStructuralTouchedResources rosterGroupId weekOffset)
    if wasCreated
        then invalidateTouchedResources "roster.week.ensure" mutationResult
        else pure mutationResult

copyRosterWeekFromSourceMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ShiftCopyOccurrenceSelections -> Id RosterGroup -> RosterWeek -> Int -> IO (Either RosterWeekCopyError (LiveMutationResult RosterWeek))
copyRosterWeekFromSourceMutation selections rosterGroupId sourceWeek targetWeekOffset = do
    copyResult <- withTransaction do
        existingTarget <- query @RosterWeek
            |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
            |> filterWhere (#weekOffset, targetWeekOffset)
            |> fetchOneOrNothing
        case existingTarget of
            Just targetWeek -> replaceRosterWeekFromSource selections sourceWeek targetWeek
            Nothing         -> copyRosterWeek selections sourceWeek targetWeekOffset
    traverse
        (\targetWeek -> invalidateTouchedResources "roster.week.copy" (liveMutationResult targetWeek (rosterWeekStructuralTouchedResources rosterGroupId targetWeekOffset)))
        copyResult

toggleRosterWeekLiveStatusMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> Bool -> IO (Either Text (LiveMutationResult RosterWeek))
toggleRosterWeekLiveStatusMutation rosterGroupId rosterWeek nextLiveStatus = do
    publishValidationError <- validateRosterWeekCanGoLive rosterWeek nextLiveStatus
    case publishValidationError of
        Just message -> pure (Left message)
        Nothing -> do
            updatedRosterWeek <-
                rosterWeek
                    |> set #isLive nextLiveStatus
                    |> updateRecord
            mutationResult <- invalidateTouchedResources
                "roster.week.live_status"
                ( liveMutationResult
                    updatedRosterWeek
                    (rosterWeekLiveStatusTouchedResources rosterGroupId rosterWeek)
                )
            pure (Right mutationResult)

appendRosterWeekSlotDefinitionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> Text -> IO (LiveMutationResult RosterWeekSlotDefinition)
appendRosterWeekSlotDefinitionMutation rosterGroupId rosterWeek slotName = do
    slotDefinition <- withTransaction (appendRosterWeekSlotDefinition rosterWeek slotName)
    invalidateTouchedResources "roster.slot_definition.append" (liveMutationResult slotDefinition (rosterSlotsStructureTouchedResources rosterGroupId rosterWeek.weekOffset))

removeRosterWeekSlotDefinitionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterWeekSlotDefinition -> IO (LiveMutationResult ())
removeRosterWeekSlotDefinitionMutation rosterGroupId rosterWeek slotDefinition = do
    withTransaction (deleteRosterWeekSlotDefinition slotDefinition)
    invalidateTouchedResources "roster.slot_definition.remove" (liveMutationResult () (rosterSlotsStructureTouchedResources rosterGroupId rosterWeek.weekOffset))

repackRosterWeekMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWeek -> IO (LiveMutationResult ())
repackRosterWeekMutation rosterWeek = do
    let rosterGroupId = coerce rosterWeek.rosterGroupId
    withTransaction (repackRosterWeekDays rosterWeek)
    invalidateTouchedResources "roster.week.repack" (liveMutationResult () (rosterSlotsStructureTouchedResources rosterGroupId rosterWeek.weekOffset))

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

withRosterSlotStaffLocks :: (?modelContext :: ModelContext) => [RosterSlot] -> IO (Either Text result) -> IO (Either Text result)
withRosterSlotStaffLocks rosterSlots action = do
    let staffIds = nub (mapMaybe (.staffId) rosterSlots)
    maybeResult <- withStaffOperationalLocks staffIds action
    pure (fromMaybe (Left rosterSlotStaffUnavailableMessage) maybeResult)

rosterSlotStillMatches :: (?modelContext :: ModelContext) => RosterSlot -> IO Bool
rosterSlotStillMatches expectedSlot = do
    _lockedSlotIds :: [PG.Only UUID] <- sqlQuery
        "SELECT id FROM roster_slots WHERE id = ? FOR UPDATE"
        (PG.Only (unpackId expectedSlot.id))
    maybeCurrentSlot <- query @RosterSlot
        |> filterWhere (#id, expectedSlot.id)
        |> filterWhere (#deletedAt, Nothing)
        |> fetchOneOrNothing
    pure (maybe False ((== expectedSlot.staffId) . (.staffId)) maybeCurrentSlot)

rosterSlotStaffUnavailableMessage :: Text
rosterSlotStaffUnavailableMessage = "The selected staff member or roster shift is no longer available for rostering."

saveRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> Maybe RosterSlot -> RosterSlot -> IO (Either Text (LiveMutationResult RosterSlotMutationResult))
saveRosterSlotMutation rosterGroupId rosterWeek rosterDay existingSlot newSlot = do
    persistenceResult <- withRosterSlotStaffLocks (newSlot : maybeToList existingSlot) do
        existingSlotMatches <- maybe (pure True) rosterSlotStillMatches existingSlot
        validationError <- if existingSlotMatches
            then validateRosterSlotForPersistence (Id rosterWeek.venueId) newSlot
            else pure (Just rosterSlotStaffUnavailableMessage)
        case validationError of
            Just message -> pure (Left message)
            Nothing -> do
                when (newSlot.rowIndex >= rosterDay.rowCount) do
                    _ <- rosterDay
                        |> set #rowCount (newSlot.rowIndex + 1)
                        |> updateRecord
                    pure ()
                persistedSlot <-
                    case existingSlot of
                        Just _  -> updateRecord newSlot
                        Nothing -> createRecord newSlot
                pure (Right persistedSlot)
    case persistenceResult of
        Left message -> pure (Left message)
        Right persistedSlot -> do
            mutationResult <- invalidateTouchedResources "roster.slot.save" (liveMutationResult (RosterSlotMutationResult (Just persistedSlot) Nothing False) (rosterSlotMutationTouchedResources rosterGroupId rosterWeek rosterDay (Just persistedSlot)))
            pure (Right mutationResult)

moveRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> RosterDay -> RosterSlot -> RosterSlot -> IO (Either Text (LiveMutationResult RosterSlotMutationResult))
moveRosterSlotMutation rosterGroupId rosterWeek sourceRosterDay targetRosterDay originalSlot updatedSlot = do
    persistenceResult <- withRosterSlotStaffLocks [originalSlot, updatedSlot] do
        originalSlotMatches <- rosterSlotStillMatches originalSlot
        validationError <- if originalSlotMatches
            then validateRosterSlotForPersistence (Id rosterWeek.venueId) updatedSlot
            else pure (Just rosterSlotStaffUnavailableMessage)
        case validationError of
            Just message -> pure (Left message)
            Nothing -> do
                when (updatedSlot.rowIndex >= targetRosterDay.rowCount) do
                    _ <- targetRosterDay
                        |> set #rowCount (updatedSlot.rowIndex + 1)
                        |> updateRecord
                    pure ()
                persistedSlot <- updateRecord updatedSlot
                shouldWarnSourceTimesheetUnchanged <- rosterSlotTimesheetSourceChangeRequiresWarning originalSlot updatedSlot
                pure (Right (persistedSlot, shouldWarnSourceTimesheetUnchanged))
    case persistenceResult of
        Left message -> pure (Left message)
        Right (persistedSlot, shouldWarnSourceTimesheetUnchanged) -> do
            let previousStaffId = originalSlot.staffId
            mutationResult <- invalidateTouchedResources "roster.slot.move" $
                liveMutationResult
                    RosterSlotMutationResult
                        { rosterSlotMutationSlot = Just persistedSlot
                        , rosterSlotMutationPreviousStaffId = previousStaffId
                        , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged
                        }
                    (nub (rosterDayTouchedResources rosterGroupId rosterWeek.weekOffset sourceRosterDay <> rosterSlotMutationTouchedResources rosterGroupId rosterWeek targetRosterDay (Just persistedSlot)))
            pure (Right mutationResult)

updateRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> RosterSlot -> RosterSlot -> IO (Either Text (LiveMutationResult RosterSlotMutationResult))
updateRosterSlotMutation rosterGroupId rosterWeek rosterDay originalSlot updatedSlot = do
    persistenceResult <- withRosterSlotStaffLocks [originalSlot, updatedSlot] do
        originalSlotMatches <- rosterSlotStillMatches originalSlot
        validationError <- if originalSlotMatches
            then validateRosterSlotForPersistence (Id rosterWeek.venueId) updatedSlot
            else pure (Just rosterSlotStaffUnavailableMessage)
        case validationError of
            Just message -> pure (Left message)
            Nothing -> do
                persistedSlot <- updateRecord updatedSlot
                shouldWarnSourceTimesheetUnchanged <- rosterSlotTimesheetSourceChangeRequiresWarning originalSlot updatedSlot
                pure (Right (persistedSlot, shouldWarnSourceTimesheetUnchanged))
    case persistenceResult of
        Left message -> pure (Left message)
        Right (persistedSlot, shouldWarnSourceTimesheetUnchanged) -> do
            let previousStaffId = originalSlot.staffId
            mutationResult <- invalidateTouchedResources "roster.slot.update" $
                liveMutationResult
                    RosterSlotMutationResult
                        { rosterSlotMutationSlot = Just persistedSlot
                        , rosterSlotMutationPreviousStaffId = previousStaffId
                        , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged
                        }
                    (rosterSlotMutationTouchedResources rosterGroupId rosterWeek rosterDay (Just persistedSlot))
            pure (Right mutationResult)


deleteRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> RosterSlot -> IO (Either Text (LiveMutationResult RosterSlotMutationResult))
deleteRosterSlotMutation rosterGroupId rosterWeek rosterDay rosterSlot = do
    deletionResult <- withRosterSlotStaffLocks [rosterSlot] do
        slotMatches <- rosterSlotStillMatches rosterSlot
        if not slotMatches
            then pure (Left rosterSlotStaffUnavailableMessage)
            else do
                now <- getCurrentTime
                deletedSlot <- rosterSlot
                    |> set #deletedAt (Just now)
                    |> set #deletedByUserId (Just (unpackId currentUser.id))
                    |> set #deleteReason (Just "roster_slot_deleted_from_dialog")
                    |> updateRecord
                pure (Right deletedSlot)
    case deletionResult of
        Left message -> pure (Left message)
        Right deletedSlot -> do
            let previousStaffId = rosterSlot.staffId
            mutationResult <- invalidateTouchedResources "roster.slot.delete" $
                liveMutationResult
                    RosterSlotMutationResult
                        { rosterSlotMutationSlot = Nothing
                        , rosterSlotMutationPreviousStaffId = previousStaffId
                        , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = False
                        }
                    (rosterSlotMutationTouchedResources rosterGroupId rosterWeek rosterDay (Just deletedSlot))
            pure (Right mutationResult)

rosterWeekTouchedResources :: Id RosterGroup -> Int -> [SurfaceResourceValue]
rosterWeekTouchedResources rosterGroupId weekOffset =
    [ rosterWeekResource (unpackId rosterGroupId) weekOffset ]

rosterWeekStructuralTouchedResources :: Id RosterGroup -> Int -> [SurfaceResourceValue]
rosterWeekStructuralTouchedResources rosterGroupId weekOffset =
    rosterWeekTouchedResources rosterGroupId weekOffset
        <> [rosterWeekStructureResource (unpackId rosterGroupId) weekOffset]

rosterSlotsStructureTouchedResources :: Id RosterGroup -> Int -> [SurfaceResourceValue]
rosterSlotsStructureTouchedResources rosterGroupId weekOffset =
    rosterWeekTouchedResources rosterGroupId weekOffset
        <> [rosterSlotsStructureResource (unpackId rosterGroupId) weekOffset]

rosterDayTouchedResources :: Id RosterGroup -> Int -> RosterDay -> [SurfaceResourceValue]
rosterDayTouchedResources rosterGroupId weekOffset rosterDay =
    rosterWeekTouchedResources rosterGroupId weekOffset
        <> [rosterDayResource (unpackId rosterDay.id)]

rosterSlotTouchedResources :: Id RosterGroup -> Int -> RosterDay -> Maybe RosterSlot -> [SurfaceResourceValue]
rosterSlotTouchedResources rosterGroupId weekOffset rosterDay maybeSlot =
    rosterDayTouchedResources rosterGroupId weekOffset rosterDay

rosterWeekLiveStatusTouchedResources :: Id RosterGroup -> RosterWeek -> [SurfaceResourceValue]
rosterWeekLiveStatusTouchedResources rosterGroupId rosterWeek =
    rosterWeekStructuralTouchedResources rosterGroupId rosterWeek.weekOffset
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

rosterSlotHasGeneratedTimesheet :: (?modelContext :: ModelContext) => RosterSlot -> IO Bool
rosterSlotHasGeneratedTimesheet rosterSlot =
    query @TimesheetEntry
        |> filterWhere (#sourceRosterSlotId, Just (unpackId rosterSlot.id))
        |> filterWhere (#deletedAt, Nothing)
        |> fetchExists

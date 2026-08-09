module Web.RosterWeeks.Mutations
    ( RosterSlotMutationResult (..)
    , addRosterDayRowMutation
    , appendRosterWindowLaneMutation
    , copyRosterWeekFromSourceMutation
    , ensureRosterWeekExistsMutation
    , materializeRosterWindowMutation
    , moveRosterSlotMutation
    , removeRosterDayRowByLanesMutation
    , repackRosterWindowMutation
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
    , removeRosterWindowLaneMutation
    ) where

import Application.Helper.FrontendContract.Surface.Roster.Resource
import Application.Helper.FrontendContract.Surface.Timesheets.Resource
import Application.Helper.SurfaceResource
import Application.RosterPublication.Mutations (withRosterWindowLock)
import Application.Staff.Mutations (withStaffOperationalLocks)
import Application.VenueTime.Model (BoundaryModelError,
                                    ShiftCopyOccurrenceSelections)
import Control.Monad (guard, void)
import Data.List (nub)
import Data.Time (Day, addDays, getCurrentTime)
import Data.Traversable (traverse)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import qualified Database.PostgreSQL.Simple as PG
import Web.Controller.Prelude
import Web.RosterWeeks.DateRange (RosterWindow (..), RosterWindowDay (..),
                                  appendRosterWindowLane, fetchRosterWindow,
                                  materializeRosterWindow,
                                  removeRosterDayRowByLanes,
                                  removeRosterWindowLane, repackRosterWindow,
                                  rosterPlanningWeekForDay,
                                  rosterWindowIsPublished)
import Web.RosterWeeks.Service
import Web.SurfaceInvalidation (invalidateTouchedResources)

invalidateRosterMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> value -> IO [SurfaceResourceValue] -> IO (LiveMutationResult value)
invalidateRosterMutation label value resources = do
    touchedResources <- resources
    invalidateTouchedResources label (liveMutationResult value touchedResources)

data RosterSlotMutationResult = RosterSlotMutationResult
    { rosterSlotMutationSlot                              :: !(Maybe RosterSlot)
    , rosterSlotMutationPreviousStaffId                   :: !(Maybe UUID)
    , rosterSlotMutationShouldWarnSourceTimesheetUnchanged :: !Bool
    }

materializeRosterWindowMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ([RosterDay], Bool)
materializeRosterWindowMutation rosterGroupId weekOffset =
    withRosterWindowMutationLock rosterGroupId weekOffset $
        materializeRosterWindow currentVenueId rosterGroupId weekOffset

ensureRosterWeekExistsMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Either Text (LiveMutationResult (RosterWeek, Bool)))
ensureRosterWeekExistsMutation rosterGroupId weekOffset = do
    materialized <- withRosterWindowMutationLock rosterGroupId weekOffset do
        venueConfig <- fetchVenueConfig
        case requestRosterCalendarRevisionError venueConfig of
            Just message -> pure (Left message)
            Nothing -> Right <$> materializeRosterWindow currentVenueId rosterGroupId weekOffset
    case materialized of
        Left message -> pure (Left message)
        Right (days, wasCreated) -> do
            rosterWeek <- maybe (error "Roster window materialization produced no days") rosterPlanningWeekForDay (listToMaybe days)
            let result = (rosterWeek, wasCreated)
            touchedResources <- rosterWeekStructuralTouchedResources rosterGroupId weekOffset
            let mutationResult = liveMutationResult result touchedResources
            Right <$>
                if wasCreated
                    then invalidateTouchedResources "roster.week.ensure" mutationResult
                    else pure mutationResult

copyRosterWeekFromSourceMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ShiftCopyOccurrenceSelections -> Id RosterGroup -> RosterWeek -> Int -> IO (Either RosterWeekCopyError (LiveMutationResult RosterWeek))
copyRosterWeekFromSourceMutation selections rosterGroupId sourceWeek targetWeekOffset = do
    copyResult <- withRosterWindowMutationLock rosterGroupId targetWeekOffset do
        venueConfig <- fetchVenueConfig
        case requestRosterCalendarRevisionError venueConfig of
            Just message -> pure (Left (RosterWeekCopyPersistenceError message))
            Nothing -> do
                targetWindow <- fetchRosterWindow currentVenueId rosterGroupId (venueWeekStartDate venueConfig targetWeekOffset)
                let targetHasPublishedDay = any (maybe False ((== Published) . (.publicationState)) . (.persistedRosterDay)) targetWindow.rosterWindowProjectedDays
                existingTarget <- query @RosterWeek
                    |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
                    |> filterWhere (#weekOffset, targetWeekOffset)
                    |> fetchOneOrNothing
                case existingTarget of
                    Just targetWeek
                        | targetHasPublishedDay ->
                            pure (Left (RosterWeekCopyPersistenceError "Published roster windows are read-only. Return it to Draft before copying."))
                        | otherwise -> replaceRosterWeekFromSource selections sourceWeek targetWeek
                    Nothing
                        | targetHasPublishedDay ->
                            pure (Left (RosterWeekCopyPersistenceError "Published roster windows are read-only. Return it to Draft before copying."))
                        | any (isJust . (.persistedRosterDay)) targetWindow.rosterWindowProjectedDays ->
                            pure (Left (RosterWeekCopyPersistenceError "Date-native roster windows cannot use legacy copy."))
                        | otherwise -> copyRosterWeek selections sourceWeek targetWeekOffset
    traverse
        (\targetWeek -> invalidateRosterMutation "roster.week.copy" targetWeek (rosterWeekStructuralTouchedResources rosterGroupId targetWeekOffset))
        copyResult

toggleRosterWeekLiveStatusMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> Bool -> IO (Either Text (LiveMutationResult RosterWeek))
toggleRosterWeekLiveStatusMutation rosterGroupId rosterWeek nextLiveStatus = do
    result <- withRosterWindowMutationLock rosterGroupId rosterWeek.weekOffset do
        venueConfig <- fetchVenueConfig
        case requestRosterCalendarRevisionError venueConfig of
            Just message -> pure (Left message)
            Nothing -> do
                let windowStartDate = venueWeekStartDate venueConfig rosterWeek.weekOffset
                when (not nextLiveStatus) do
                    when (unpackId rosterWeek.id /= UUID.nil) do
                        _ <- rosterWeek |> set #isLive False |> updateRecord
                        pure ()
                    window <- fetchRosterWindow currentVenueId rosterGroupId windowStartDate
                    forM_ (mapMaybe (.persistedRosterDay) window.rosterWindowProjectedDays) \day ->
                        void (day |> set #publicationState Draft |> updateRecord)
                (rosterDays, _) <- materializeRosterWindow currentVenueId rosterGroupId rosterWeek.weekOffset
                publishValidationError <-
                    if nextLiveStatus
                        then validateRosterDaysCanPublish currentVenueId rosterDays
                        else pure Nothing
                case publishValidationError of
                    Just message -> pure (Left message)
                    Nothing -> do
                        updatedRosterWeek <-
                            if unpackId rosterWeek.id == UUID.nil
                                then pure (rosterWeek |> set #isLive nextLiveStatus)
                                else rosterWeek
                                    |> set #isLive nextLiveStatus
                                    |> updateRecord
                        let publicationState = if nextLiveStatus then Published else Draft
                        forM_ rosterDays \day ->
                            void (day |> set #publicationState publicationState |> updateRecord)
                        pure (Right updatedRosterWeek)
    case result of
        Left message -> pure (Left message)
        Right updatedRosterWeek -> do
            mutationResult <- invalidateRosterMutation
                "roster.window.publication_status"
                updatedRosterWeek
                (rosterWeekLiveStatusTouchedResources rosterGroupId rosterWeek)
            pure (Right mutationResult)

withRosterWindowMutationLock :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO value -> IO value
withRosterWindowMutationLock rosterGroupId weekOffset =
    withRosterWindowLock currentVenueId rosterGroupId weekOffset

data RosterWindowMutationAccess
    = RequireDraftWindow
    | RequirePublishedWindow

withRosterWindowPublicationAccess :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> RosterWindowMutationAccess -> IO (Either Text value) -> IO (Either Text value)
withRosterWindowPublicationAccess rosterGroupId weekOffset requiredAccess action =
    withRosterWindowMutationLock rosterGroupId weekOffset do
        venueConfig <- fetchVenueConfig
        window <- fetchRosterWindow currentVenueId rosterGroupId (venueWeekStartDate venueConfig weekOffset)
        let hasPublishedDay = any (maybe False ((== Published) . (.publicationState)) . (.persistedRosterDay)) window.rosterWindowProjectedDays
            isPublishedWindow = rosterWindowIsPublished window
        case requestRosterCalendarRevisionError venueConfig of
            Just message -> pure (Left message)
            Nothing ->
                case requiredAccess of
                    RequireDraftWindow
                        | hasPublishedDay -> pure (Left publishedRosterReadOnlyMessage)
                    RequirePublishedWindow
                        | not isPublishedWindow -> pure (Left rosterSlotStaffUnavailableMessage)
                    _ -> action

draftRosterWindowErrorUnderLock :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe Text)
draftRosterWindowErrorUnderLock rosterGroupId weekOffset = do
    venueConfig <- fetchVenueConfig
    window <- fetchRosterWindow currentVenueId rosterGroupId (venueWeekStartDate venueConfig weekOffset)
    pure $
        requestRosterCalendarRevisionError venueConfig
            <|> if any (maybe False ((== Published) . (.publicationState)) . (.persistedRosterDay)) window.rosterWindowProjectedDays
                then Just publishedRosterReadOnlyMessage
                else Nothing

requestRosterCalendarRevisionError :: (?request :: Request) => VenueConfig -> Maybe Text
requestRosterCalendarRevisionError venueConfig =
    case paramOrNothing @Int "rosterCalendarRevision" of
        Nothing -> Just "The roster calendar context is missing. Review the refreshed window and try again."
        Just expectedRevision
            | expectedRevision /= venueConfig.rosterCalendarRevision ->
                Just "The roster calendar changed. Review the refreshed window and try again."
        _ -> Nothing

publishedRosterReadOnlyMessage :: Text
publishedRosterReadOnlyMessage = "Published roster windows are read-only. Return it to Draft to make changes."

appendRosterWindowLaneMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> IO (Either Text (LiveMutationResult RosterLane))
appendRosterWindowLaneMutation rosterGroupId weekOffset laneName = do
    result <- withRosterWindowMutationLock rosterGroupId weekOffset do
        draftRosterWindowErrorUnderLock rosterGroupId weekOffset >>= \case
            Just message -> pure (Left message)
            Nothing -> appendRosterWindowLane currentVenueId rosterGroupId weekOffset laneName
    traverse (\lane -> invalidateRosterMutation "roster.lane.append" lane (rosterSlotsStructureTouchedResources rosterGroupId weekOffset)) result

removeRosterWindowLaneMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Id RosterLane -> IO (Either Text (LiveMutationResult ()))
removeRosterWindowLaneMutation rosterGroupId weekOffset laneId = do
    result <- withRosterWindowMutationLock rosterGroupId weekOffset do
        draftRosterWindowErrorUnderLock rosterGroupId weekOffset >>= \case
            Just message -> pure (Left message)
            Nothing -> removeRosterWindowLane currentVenueId rosterGroupId weekOffset laneId currentUser.id
    traverse (\() -> invalidateRosterMutation "roster.lane.remove" () (rosterSlotsStructureTouchedResources rosterGroupId weekOffset)) result

repackRosterWindowMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Either Text (LiveMutationResult ()))
repackRosterWindowMutation rosterGroupId weekOffset = do
    result <- withRosterWindowMutationLock rosterGroupId weekOffset do
        draftRosterWindowErrorUnderLock rosterGroupId weekOffset >>= \case
            Just message -> pure (Left message)
            Nothing -> repackRosterWindow currentVenueId rosterGroupId weekOffset >> pure (Right ())
    traverse (\() -> invalidateRosterMutation "roster.window.repack" () (rosterSlotsStructureTouchedResources rosterGroupId weekOffset)) result

toggleRosterDayClosedMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> Bool -> Int -> IO (Either Text (LiveMutationResult RosterDay))
toggleRosterDayClosedMutation rosterGroupId rosterWeek rosterDay nextClosedState minimumRows = do
    result <- withRosterWindowMutationLock rosterGroupId rosterWeek.weekOffset do
        draftRosterWindowErrorUnderLock rosterGroupId rosterWeek.weekOffset >>= \case
            Just message -> pure (Left message)
            Nothing -> do
                currentDay <- fetch rosterDay.id
                when nextClosedState do
                    ensureRosterDayHasMinimumRows currentDay rosterGroupId minimumRows
                Right <$> (currentDay |> set #isClosed nextClosedState |> updateRecord)
    traverse (\updatedDay -> invalidateRosterMutation "roster.day.closed" updatedDay (rosterDayTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay)) result

addRosterDayRowMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> IO (Either Text (LiveMutationResult RosterDay))
addRosterDayRowMutation rosterGroupId rosterWeek rosterDay = do
    result <- withRosterWindowMutationLock rosterGroupId rosterWeek.weekOffset do
        draftRosterWindowErrorUnderLock rosterGroupId rosterWeek.weekOffset >>= \case
            Just message -> pure (Left message)
            Nothing -> do
                currentDay <- fetch rosterDay.id
                Right <$> (currentDay |> set #rowCount (currentDay.rowCount + 1) |> updateRecord)
    traverse (\updatedDay -> invalidateRosterMutation "roster.day.row_add" updatedDay (rosterDayTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay)) result

removeRosterDayRowByLanesMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> IO (Either Text (LiveMutationResult ()))
removeRosterDayRowByLanesMutation rosterGroupId rosterWeek rosterDay = do
    result <- withRosterWindowMutationLock rosterGroupId rosterWeek.weekOffset do
        draftRosterWindowErrorUnderLock rosterGroupId rosterWeek.weekOffset >>= \case
            Just message -> pure (Left message)
            Nothing -> removeRosterDayRowByLanes rosterDay currentUser.id >> pure (Right ())
    traverse (\() -> invalidateRosterMutation "roster.row.remove" () (rosterDayTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay)) result

withRosterSlotStaffLocks :: (?modelContext :: ModelContext) => [RosterSlot] -> IO (Either Text result) -> IO (Either Text result)
withRosterSlotStaffLocks rosterSlots action = do
    let staffIds = nub (mapMaybe (.staffId) rosterSlots)
    maybeResult <- withStaffOperationalLocks staffIds action
    pure (fromMaybe (Left rosterSlotStaffUnavailableMessage) maybeResult)

withRosterWindowSlotStaffLocks :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> RosterWindowMutationAccess -> [RosterSlot] -> IO (Either Text value) -> IO (Either Text value)
withRosterWindowSlotStaffLocks rosterGroupId weekOffset requiredAccess rosterSlots action =
    withRosterWindowPublicationAccess rosterGroupId weekOffset requiredAccess $
        withRosterSlotStaffLocks rosterSlots action

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
    persistenceResult <- withRosterWindowSlotStaffLocks rosterGroupId rosterWeek.weekOffset RequireDraftWindow (newSlot : maybeToList existingSlot) do
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
            mutationResult <- invalidateRosterMutation "roster.slot.save" (RosterSlotMutationResult (Just persistedSlot) Nothing False) (rosterSlotMutationTouchedResources rosterGroupId rosterWeek rosterDay (Just persistedSlot))
            pure (Right mutationResult)

moveRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> RosterDay -> RosterSlot -> RosterSlot -> IO (Either Text (LiveMutationResult RosterSlotMutationResult))
moveRosterSlotMutation rosterGroupId rosterWeek sourceRosterDay targetRosterDay originalSlot updatedSlot = do
    persistenceResult <- withRosterWindowSlotStaffLocks rosterGroupId rosterWeek.weekOffset RequireDraftWindow [originalSlot, updatedSlot] do
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
            sourceResources <- rosterDayTouchedResources rosterGroupId rosterWeek.weekOffset sourceRosterDay
            targetResources <- rosterSlotMutationTouchedResources rosterGroupId rosterWeek targetRosterDay (Just persistedSlot)
            mutationResult <- invalidateTouchedResources "roster.slot.move" $
                liveMutationResult
                    RosterSlotMutationResult
                        { rosterSlotMutationSlot = Just persistedSlot
                        , rosterSlotMutationPreviousStaffId = previousStaffId
                        , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged
                        }
                    (nub (sourceResources <> targetResources))
            pure (Right mutationResult)

updateRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> RosterSlot -> RosterSlot -> Bool -> IO (Either Text (LiveMutationResult RosterSlotMutationResult))
updateRosterSlotMutation rosterGroupId rosterWeek rosterDay originalSlot updatedSlot allowPublishedOpenFill = do
    let requiredAccess = if allowPublishedOpenFill then RequirePublishedWindow else RequireDraftWindow
    persistenceResult <- withRosterWindowSlotStaffLocks rosterGroupId rosterWeek.weekOffset requiredAccess [originalSlot, updatedSlot] do
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
            mutationResult <- invalidateRosterMutation
                "roster.slot.update"
                RosterSlotMutationResult
                    { rosterSlotMutationSlot = Just persistedSlot
                    , rosterSlotMutationPreviousStaffId = previousStaffId
                    , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged
                    }
                (rosterSlotMutationTouchedResources rosterGroupId rosterWeek rosterDay (Just persistedSlot))
            pure (Right mutationResult)


deleteRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> RosterSlot -> IO (Either Text (LiveMutationResult RosterSlotMutationResult))
deleteRosterSlotMutation rosterGroupId rosterWeek rosterDay rosterSlot = do
    deletionResult <- withRosterWindowSlotStaffLocks rosterGroupId rosterWeek.weekOffset RequireDraftWindow [rosterSlot] do
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
            mutationResult <- invalidateRosterMutation
                "roster.slot.delete"
                RosterSlotMutationResult
                    { rosterSlotMutationSlot = Nothing
                    , rosterSlotMutationPreviousStaffId = previousStaffId
                    , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = False
                    }
                (rosterSlotMutationTouchedResources rosterGroupId rosterWeek rosterDay (Just deletedSlot))
            pure (Right mutationResult)

rosterWindowRangeForOffset :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> IO (Day, Day)
rosterWindowRangeForOffset weekOffset = do
    venueConfig <- fetchVenueConfig
    let windowStart = venueWeekStartDate venueConfig weekOffset
    pure (windowStart, addDays 7 windowStart)

rosterWeekTouchedResources :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO [SurfaceResourceValue]
rosterWeekTouchedResources rosterGroupId weekOffset = do
    (windowStart, windowEnd) <- rosterWindowRangeForOffset weekOffset
    pure [rosterWeekResource (unpackId rosterGroupId) windowStart windowEnd]

rosterWeekStructuralTouchedResources :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO [SurfaceResourceValue]
rosterWeekStructuralTouchedResources rosterGroupId weekOffset = do
    (windowStart, windowEnd) <- rosterWindowRangeForOffset weekOffset
    resources <- rosterWeekTouchedResources rosterGroupId weekOffset
    pure (resources <> [rosterWeekStructureResource (unpackId rosterGroupId) windowStart windowEnd])

rosterSlotsStructureTouchedResources :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO [SurfaceResourceValue]
rosterSlotsStructureTouchedResources rosterGroupId weekOffset = do
    (windowStart, windowEnd) <- rosterWindowRangeForOffset weekOffset
    resources <- rosterWeekTouchedResources rosterGroupId weekOffset
    pure (resources <> [rosterSlotsStructureResource (unpackId rosterGroupId) windowStart windowEnd])

rosterDayTouchedResources :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> RosterDay -> IO [SurfaceResourceValue]
rosterDayTouchedResources rosterGroupId weekOffset rosterDay = do
    resources <- rosterWeekTouchedResources rosterGroupId weekOffset
    pure (resources <> [rosterDayResource (unpackId rosterDay.id)])

rosterSlotTouchedResources :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> RosterDay -> Maybe RosterSlot -> IO [SurfaceResourceValue]
rosterSlotTouchedResources rosterGroupId weekOffset rosterDay _maybeSlot =
    rosterDayTouchedResources rosterGroupId weekOffset rosterDay

rosterWeekLiveStatusTouchedResources :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> RosterWeek -> IO [SurfaceResourceValue]
rosterWeekLiveStatusTouchedResources rosterGroupId rosterWeek = do
    rosterResources <- rosterWeekStructuralTouchedResources rosterGroupId rosterWeek.weekOffset
    timesheetResources <- timesheetWeekTouchedResources rosterWeek
    pure (rosterResources <> timesheetResources)

rosterSlotMutationTouchedResources :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> RosterWeek -> RosterDay -> Maybe RosterSlot -> IO [SurfaceResourceValue]
rosterSlotMutationTouchedResources rosterGroupId rosterWeek rosterDay maybeSlot = do
    rosterResources <- rosterSlotTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay maybeSlot
    timesheetResources <- timesheetWeekTouchedResources rosterWeek
    pure (rosterResources <> timesheetResources)

timesheetWeekTouchedResources :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWeek -> IO [SurfaceResourceValue]
timesheetWeekTouchedResources rosterWeek = do
    (windowStart, windowEnd) <- rosterWindowRangeForOffset rosterWeek.weekOffset
    pure [timesheetWeekResource rosterWeek.venueId windowStart windowEnd]

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

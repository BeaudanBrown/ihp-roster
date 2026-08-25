module Web.RosterWeeks.Mutations
    ( RosterSlotMutationResult (..)
    , addRosterDayRowMutation
    , appendRosterWindowLaneMutation
    , copyRosterWindowFromSourceMutation
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
import Application.Helper.FrontendContract.Surface.Timesheets.Live (activeTimesheetWindowScopes)
import Application.Helper.FrontendContract.Surface.Timesheets.Resource
import Application.Helper.LiveUpdate.DurablePublisher (persistDurableInvalidationInCurrentTransaction)
import Application.Helper.SurfaceResource
import Application.RosterPublication.Mutations (withRosterWindowDateLockInCurrentTransaction)
import Application.Staff.Mutations (withStaffOperationalLocksInCurrentTransaction)
import Application.VenueTime.Model (ShiftCopyOccurrenceSelections)
import Control.Monad (guard, void)
import Data.List (nub)
import qualified Data.Set as Set
import Data.Time (Day, addDays, getCurrentTime)
import Data.Traversable (traverse)
import Data.UUID (UUID)
import qualified Database.PostgreSQL.Simple as PG
import Network.HTTP.Types.Status (status409)
import qualified Network.Wai as Wai
import Web.Controller.Prelude
import Web.RosterWeeks.DateRange (RosterWindow (..), RosterWindowDay (..),
                                  RosterWindowScope (..),
                                  RosterWindowState (..),
                                  appendRosterWindowLane, fetchRosterWindow,
                                  materializeRosterWindow,
                                  removeRosterDayRowByLanes,
                                  removeRosterWindowLane, repackRosterWindow,
                                  rosterWindowIsPublished)
import Web.RosterWeeks.Service
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)

withDurableRosterMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    ((?modelContext :: ModelContext) => IO (Either error (LiveMutationResult value))) ->
    IO (Either error (LiveMutationResult value))
withDurableRosterMutation label =
    withDurableLiveMutationOutcome (either (const Nothing) (\result -> Just (label, result.liveMutationTouchedResources)))

rosterMutationResult :: value -> IO [SurfaceResourceValue] -> IO (LiveMutationResult value)
rosterMutationResult value resources = do
    touchedResources <- resources
    pure (liveMutationResult value touchedResources)

data RosterSlotMutationResult = RosterSlotMutationResult
    { rosterSlotMutationSlot                              :: !(Maybe RosterSlot)
    , rosterSlotMutationPreviousStaffId                   :: !(Maybe UUID)
    , rosterSlotMutationShouldWarnSourceTimesheetUnchanged :: !Bool
    }

materializeRosterWindowMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO ([RosterDay], Bool)
materializeRosterWindowMutation scope =
    withRosterWindowMutationLock scope $
        materializeRosterWindow scope

ensureRosterWeekExistsMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO (Either Text (LiveMutationResult (RosterWindowState, Bool)))
ensureRosterWeekExistsMutation scope =
    withDurableLiveMutationOutcome publicationFor do
        materialized <- withRosterWindowMutationLock scope do
            venueConfig <- fetchVenueConfig
            calendarError <- requestRosterCalendarRevisionError venueConfig
            case calendarError of
                Just message -> pure (Left message)
                Nothing      -> Right <$> materializeRosterWindow scope
        case materialized of
            Left message -> pure (Left message)
            Right (_days, wasCreated) -> do
                let windowState = RosterWindowState
                        { windowRosterGroupId = unpackId scope.rosterWindowRosterGroupId
                        , windowIsPublished = False
                        , windowHasPublishedDays = False
                        }
                let result = (windowState, wasCreated)
                pure (Right (liveMutationResult result (rosterWeekStructuralTouchedResources scope)))
  where
    publicationFor (Right result)
        | snd result.liveMutationValue = Just ("roster.week.ensure", result.liveMutationTouchedResources)
    publicationFor _ = Nothing

copyRosterWindowFromSourceMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    ShiftCopyOccurrenceSelections ->
    Id RosterGroup ->
    Day ->
    Day ->
    IO (Either RosterCopyError (LiveMutationResult ()))
copyRosterWindowFromSourceMutation selections rosterGroupId sourceStart targetStart = do
    venueConfig <- fetchVenueConfig
    let targetScope = RosterWindowScope
            { rosterWindowVenueId = currentVenueId
            , rosterWindowRosterGroupId = rosterGroupId
            , rosterWindowStart = targetStart
            , rosterWindowEnd = addDays 7 targetStart
            , rosterWindowCalendarRevision = venueConfig.rosterCalendarRevision
            }
    withRosterCopyTransaction do
        copyResult <- withRosterWindowMutationLock targetScope do
            lockedVenueConfig <- fetchVenueConfig
            calendarError <- requestRosterCalendarRevisionError lockedVenueConfig
            case calendarError of
                Just _message -> pure (Left RosterCopyPersistenceRejected)
                Nothing -> do
                    targetWindow <- fetchRosterWindow currentVenueId rosterGroupId targetStart
                    let targetHasPublishedDay = any (maybe False ((== Published) . (.publicationState)) . (.persistedRosterDay)) targetWindow.rosterWindowProjectedDays
                    if targetHasPublishedDay
                        then pure (Left RosterCopyTargetPublished)
                        else copyRosterWindowByDates selections currentVenueId rosterGroupId sourceStart targetStart
        case copyResult of
            Left copyError -> pure (Left copyError)
            Right () -> do
                let result = liveMutationResult () (rosterWeekStructuralTouchedResources targetScope)
                _ <- persistDurableInvalidationInCurrentTransaction "roster.window.copy" result.liveMutationTouchedResources
                pure (Right result)

toggleRosterWeekLiveStatusMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterWindowState -> Bool -> IO (Either Text (LiveMutationResult RosterWindowState))
toggleRosterWeekLiveStatusMutation scope windowState nextLiveStatus =
    withDurableRosterMutation "roster.window.publication_status" do
        result <- withRosterWindowMutationLock scope do
            venueConfig <- fetchVenueConfig
            calendarError <- requestRosterCalendarRevisionError venueConfig
            case calendarError of
                Just message -> pure (Left message)
                Nothing -> do
                    let windowStartDate = scope.rosterWindowStart
                    when (not nextLiveStatus) do
                        window <- fetchRosterWindow scope.rosterWindowVenueId scope.rosterWindowRosterGroupId windowStartDate
                        forM_ (mapMaybe (.persistedRosterDay) window.rosterWindowProjectedDays) \day ->
                            void (day |> set #publicationState Draft |> updateRecord)
                    (rosterDays, _) <- materializeRosterWindow scope
                    publishValidationError <-
                        if nextLiveStatus
                            then validateRosterDaysCanPublish currentVenueId rosterDays
                            else pure Nothing
                    case publishValidationError of
                        Just message -> pure (Left message)
                        Nothing -> do
                            let updatedWindowState = windowState { windowIsPublished = nextLiveStatus, windowHasPublishedDays = nextLiveStatus }
                            let publicationState = if nextLiveStatus then Published else Draft
                            forM_ rosterDays \day ->
                                void (day |> set #publicationState publicationState |> updateRecord)
                            pure (Right updatedWindowState)
        case result of
            Left message -> pure (Left message)
            Right updatedWindowState -> do
                mutationResult <- rosterMutationResult updatedWindowState (rosterWeekLiveStatusTouchedResources scope)
                pure (Right mutationResult)

withRosterWindowMutationLock :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO value -> IO value
withRosterWindowMutationLock scope =
    withRosterWindowDateLockInCurrentTransaction
        scope.rosterWindowVenueId
        scope.rosterWindowRosterGroupId
        scope.rosterWindowStart
        scope.rosterWindowEnd

data RosterWindowMutationAccess
    = RequireDraftWindow
    | RequirePublishedWindow

withRosterWindowPublicationAccess :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterWindowMutationAccess -> IO (Either Text value) -> IO (Either Text value)
withRosterWindowPublicationAccess scope requiredAccess action =
    withRosterWindowMutationLock scope do
        venueConfig <- fetchVenueConfig
        window <- fetchRosterWindow scope.rosterWindowVenueId scope.rosterWindowRosterGroupId scope.rosterWindowStart
        let hasPublishedDay = any (maybe False ((== Published) . (.publicationState)) . (.persistedRosterDay)) window.rosterWindowProjectedDays
            isPublishedWindow = rosterWindowIsPublished window
        calendarError <- requestRosterCalendarRevisionError venueConfig
        case calendarError of
            Just message -> pure (Left message)
            Nothing ->
                case requiredAccess of
                    RequireDraftWindow
                        | hasPublishedDay -> pure (Left publishedRosterReadOnlyMessage)
                    RequirePublishedWindow
                        | not isPublishedWindow -> pure (Left rosterSlotStaffUnavailableMessage)
                    _ -> action

draftRosterWindowErrorUnderLock :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO (Maybe Text)
draftRosterWindowErrorUnderLock scope = do
    venueConfig <- fetchVenueConfig
    window <- fetchRosterWindow scope.rosterWindowVenueId scope.rosterWindowRosterGroupId scope.rosterWindowStart
    calendarError <- requestRosterCalendarRevisionError venueConfig
    pure (calendarError <|> guardPublishedWindow window)

requestRosterCalendarRevisionError :: (?context :: ControllerContext, ?request :: Request) => VenueConfig -> IO (Maybe Text)
requestRosterCalendarRevisionError venueConfig =
    case paramOrNothing @Int "rosterCalendarRevision" of
        Nothing -> staleCalendarError "The roster calendar context is missing. Review the refreshed window and try again."
        Just expectedRevision
            | expectedRevision /= venueConfig.rosterCalendarRevision ->
                staleCalendarError "The roster calendar changed. Review the refreshed window and try again."
        _ -> pure Nothing
  where
    staleCalendarError message
        | isHtmxRequest = do
            respondAndExit
                ( Wai.responseLBS
                    status409
                    [("Content-Type", "text/plain"), ("HX-Refresh", "true")]
                    (cs message)
                )
            error "unreachable"
        | otherwise = pure (Just message)

guardPublishedWindow :: RosterWindow -> Maybe Text
guardPublishedWindow window
    | any (maybe False ((== Published) . (.publicationState)) . (.persistedRosterDay)) window.rosterWindowProjectedDays = Just publishedRosterReadOnlyMessage
    | otherwise = Nothing

publishedRosterReadOnlyMessage :: Text
publishedRosterReadOnlyMessage = "Published roster windows are read-only. Return it to Draft to make changes."

appendRosterWindowLaneMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Text -> IO (Either Text (LiveMutationResult RosterLane))
appendRosterWindowLaneMutation scope laneName =
    withDurableRosterMutation "roster.lane.append" do
        result <- withRosterWindowMutationLock scope do
            draftRosterWindowErrorUnderLock scope >>= \case
                Just message -> pure (Left message)
                Nothing -> appendRosterWindowLane scope laneName
        traverse (\lane -> rosterMutationResult lane (pure (rosterSlotsStructureTouchedResources scope))) result

removeRosterWindowLaneMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Id RosterLane -> IO (Either Text (LiveMutationResult ()))
removeRosterWindowLaneMutation scope laneId =
    withDurableRosterMutation "roster.lane.remove" do
        result <- withRosterWindowMutationLock scope do
            draftRosterWindowErrorUnderLock scope >>= \case
                Just message -> pure (Left message)
                Nothing -> removeRosterWindowLane scope laneId currentUser.id
        traverse (\() -> rosterMutationResult () (pure (rosterSlotsStructureTouchedResources scope))) result

repackRosterWindowMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO (Either Text (LiveMutationResult ()))
repackRosterWindowMutation scope =
    withDurableRosterMutation "roster.window.repack" do
        result <- withRosterWindowMutationLock scope do
            draftRosterWindowErrorUnderLock scope >>= \case
                Just message -> pure (Left message)
                Nothing -> repackRosterWindow scope >> pure (Right ())
        traverse (\() -> rosterMutationResult () (pure (rosterSlotsStructureTouchedResources scope))) result

toggleRosterDayClosedMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> Bool -> Int -> IO (Either Text (LiveMutationResult RosterDay))
toggleRosterDayClosedMutation scope rosterDay nextClosedState minimumRows =
    withDurableRosterMutation "roster.day.closed" do
        result <- withRosterWindowMutationLock scope do
            draftRosterWindowErrorUnderLock scope >>= \case
                Just message -> pure (Left message)
                Nothing -> do
                    currentDay <- fetch rosterDay.id
                    when nextClosedState do
                        ensureRosterDayHasMinimumRows currentDay scope.rosterWindowRosterGroupId minimumRows
                    Right <$> (currentDay |> set #isClosed nextClosedState |> updateRecord)
        traverse (\updatedDay -> rosterMutationResult updatedDay (pure (rosterDayTouchedResources scope rosterDay))) result

addRosterDayRowMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> IO (Either Text (LiveMutationResult RosterDay))
addRosterDayRowMutation scope rosterDay =
    withDurableRosterMutation "roster.day.row_add" do
        result <- withRosterWindowMutationLock scope do
            draftRosterWindowErrorUnderLock scope >>= \case
                Just message -> pure (Left message)
                Nothing -> do
                    currentDay <- fetch rosterDay.id
                    Right <$> (currentDay |> set #rowCount (currentDay.rowCount + 1) |> updateRecord)
        traverse (\updatedDay -> rosterMutationResult updatedDay (pure (rosterDayTouchedResources scope rosterDay))) result

removeRosterDayRowByLanesMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> IO (Either Text (LiveMutationResult ()))
removeRosterDayRowByLanesMutation scope rosterDay =
    withDurableRosterMutation "roster.row.remove" do
        result <- withRosterWindowMutationLock scope do
            draftRosterWindowErrorUnderLock scope >>= \case
                Just message -> pure (Left message)
                Nothing -> removeRosterDayRowByLanes rosterDay currentUser.id >> pure (Right ())
        traverse (\() -> rosterMutationResult () (pure (rosterDayTouchedResources scope rosterDay))) result

withRosterSlotStaffLocks :: (?modelContext :: ModelContext) => [RosterSlot] -> IO (Either Text result) -> IO (Either Text result)
withRosterSlotStaffLocks rosterSlots action = do
    let staffIds = nub (mapMaybe (.staffId) rosterSlots)
    maybeResult <- withStaffOperationalLocksInCurrentTransaction staffIds action
    pure (fromMaybe (Left rosterSlotStaffUnavailableMessage) maybeResult)

withRosterWindowSlotStaffLocks :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterWindowMutationAccess -> [RosterSlot] -> IO (Either Text value) -> IO (Either Text value)
withRosterWindowSlotStaffLocks scope requiredAccess rosterSlots action =
    withRosterWindowPublicationAccess scope requiredAccess $
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

saveRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> Maybe RosterSlot -> RosterSlot -> IO (Either Text (LiveMutationResult RosterSlotMutationResult))
saveRosterSlotMutation scope rosterDay existingSlot newSlot =
    withDurableRosterMutation "roster.slot.save" do
        persistenceResult <- withRosterWindowSlotStaffLocks scope RequireDraftWindow (newSlot : maybeToList existingSlot) do
            existingSlotMatches <- maybe (pure True) rosterSlotStillMatches existingSlot
            validationError <- if existingSlotMatches
                then validateRosterSlotForPersistence scope.rosterWindowVenueId newSlot
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
                mutationResult <- rosterMutationResult (RosterSlotMutationResult (Just persistedSlot) Nothing False) (rosterSlotMutationTouchedResources scope rosterDay (Just persistedSlot))
                pure (Right mutationResult)

moveRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> RosterDay -> RosterSlot -> RosterSlot -> IO (Either Text (LiveMutationResult RosterSlotMutationResult))
moveRosterSlotMutation scope sourceRosterDay targetRosterDay originalSlot updatedSlot =
    withDurableRosterMutation "roster.slot.move" do
        persistenceResult <- withRosterWindowSlotStaffLocks scope RequireDraftWindow [originalSlot, updatedSlot] do
            originalSlotMatches <- rosterSlotStillMatches originalSlot
            validationError <- if originalSlotMatches
                then validateRosterSlotForPersistence scope.rosterWindowVenueId updatedSlot
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
                let sourceResources = rosterDayTouchedResources scope sourceRosterDay
                targetResources <- rosterSlotMutationTouchedResources scope targetRosterDay (Just persistedSlot)
                let mutationResult =
                        liveMutationResult
                        RosterSlotMutationResult
                            { rosterSlotMutationSlot = Just persistedSlot
                            , rosterSlotMutationPreviousStaffId = previousStaffId
                            , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged
                            }
                        (nub (sourceResources <> targetResources))
                pure (Right mutationResult)

updateRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> RosterSlot -> RosterSlot -> Bool -> IO (Either Text (LiveMutationResult RosterSlotMutationResult))
updateRosterSlotMutation scope rosterDay originalSlot updatedSlot allowPublishedOpenFill =
    withDurableRosterMutation "roster.slot.update" do
        let requiredAccess = if allowPublishedOpenFill then RequirePublishedWindow else RequireDraftWindow
        persistenceResult <- withRosterWindowSlotStaffLocks scope requiredAccess [originalSlot, updatedSlot] do
            originalSlotMatches <- rosterSlotStillMatches originalSlot
            validationError <- if originalSlotMatches
                then validateRosterSlotForPersistence scope.rosterWindowVenueId updatedSlot
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
                mutationResult <- rosterMutationResult
                    RosterSlotMutationResult
                        { rosterSlotMutationSlot = Just persistedSlot
                        , rosterSlotMutationPreviousStaffId = previousStaffId
                        , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged
                        }
                    (rosterSlotMutationTouchedResources scope rosterDay (Just persistedSlot))
                pure (Right mutationResult)


deleteRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> RosterSlot -> IO (Either Text (LiveMutationResult RosterSlotMutationResult))
deleteRosterSlotMutation scope rosterDay rosterSlot =
    withDurableRosterMutation "roster.slot.delete" do
        deletionResult <- withRosterWindowSlotStaffLocks scope RequireDraftWindow [rosterSlot] do
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
                mutationResult <- rosterMutationResult
                    RosterSlotMutationResult
                        { rosterSlotMutationSlot = Nothing
                        , rosterSlotMutationPreviousStaffId = previousStaffId
                        , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = False
                        }
                    (rosterSlotMutationTouchedResources scope rosterDay (Just deletedSlot))
                pure (Right mutationResult)

rosterWeekTouchedResources :: RosterWindowScope -> [SurfaceResourceValue]
rosterWeekTouchedResources scope =
    [rosterWeekResource (unpackId scope.rosterWindowRosterGroupId) scope.rosterWindowStart scope.rosterWindowEnd]

rosterWeekStructuralTouchedResources :: RosterWindowScope -> [SurfaceResourceValue]
rosterWeekStructuralTouchedResources scope =
    rosterWeekTouchedResources scope
        <> [rosterWeekStructureResource (unpackId scope.rosterWindowRosterGroupId) scope.rosterWindowStart scope.rosterWindowEnd]

rosterSlotsStructureTouchedResources :: RosterWindowScope -> [SurfaceResourceValue]
rosterSlotsStructureTouchedResources scope =
    rosterWeekTouchedResources scope
        <> [rosterSlotsStructureResource (unpackId scope.rosterWindowRosterGroupId) scope.rosterWindowStart scope.rosterWindowEnd]

rosterDayTouchedResources :: RosterWindowScope -> RosterDay -> [SurfaceResourceValue]
rosterDayTouchedResources scope rosterDay =
    rosterWeekTouchedResources scope <> [rosterDayResource (unpackId rosterDay.id)]

rosterSlotTouchedResources :: RosterWindowScope -> RosterDay -> Maybe RosterSlot -> [SurfaceResourceValue]
rosterSlotTouchedResources scope rosterDay _maybeSlot =
    rosterDayTouchedResources scope rosterDay

rosterWeekLiveStatusTouchedResources :: RosterWindowScope -> IO [SurfaceResourceValue]
rosterWeekLiveStatusTouchedResources scope = do
    timesheetResources <- timesheetWeekTouchedResources scope
    pure (rosterWeekStructuralTouchedResources scope <> timesheetResources)

rosterSlotMutationTouchedResources :: RosterWindowScope -> RosterDay -> Maybe RosterSlot -> IO [SurfaceResourceValue]
rosterSlotMutationTouchedResources scope rosterDay maybeSlot = do
    let rosterResources = rosterSlotTouchedResources scope rosterDay maybeSlot
    timesheetResources <- timesheetWeekTouchedResources scope
    pure (rosterResources <> timesheetResources)

timesheetWeekTouchedResources :: RosterWindowScope -> IO [SurfaceResourceValue]
timesheetWeekTouchedResources scope = do
    activeScopes <- activeTimesheetWindowScopes
    pure $ Set.toList $ Set.fromList $
        timesheetWeekResource (unpackId scope.rosterWindowVenueId) scope.rosterWindowStart scope.rosterWindowEnd
            : [ timesheetWeekResource activeVenueId windowStart windowEnd
              | (activeVenueId, windowStart, windowEnd, _calendarRevision) <- activeScopes
              , activeVenueId == unpackId scope.rosterWindowVenueId
              , windowStart < scope.rosterWindowEnd
              , windowEnd > scope.rosterWindowStart
              ]

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

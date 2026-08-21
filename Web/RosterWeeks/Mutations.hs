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
import Application.Helper.FrontendContract.Surface.Timesheets.Resource
import Application.Helper.SurfaceResource
import Application.RosterPublication.Mutations (withRosterWindowDateLock)
import Application.Staff.Mutations (withStaffOperationalLocks)
import Application.VenueTime.Model (ShiftCopyOccurrenceSelections)
import Control.Monad (guard, void)
import Data.List (nub)
import Data.Time (Day, addDays, getCurrentTime)
import Data.Traversable (traverse)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import qualified Database.PostgreSQL.Simple as PG
import Network.HTTP.Types.Status (status409)
import qualified Network.Wai as Wai
import Web.Controller.Prelude
import Web.RosterWeeks.DateRange (RosterWindow (..), RosterWindowDay (..),
                                  RosterWindowScope (..),
                                  appendRosterWindowLane, fetchRosterWindow,
                                  materializeRosterWindow,
                                  removeRosterDayRowByLanes,
                                  removeRosterWindowLane, repackRosterWindow,
                                  rosterWindowIsPublished)
import Web.RosterWeeks.LegacyCompatibility (legacyPlanningRosterWeekForScope)
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

materializeRosterWindowMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO ([RosterDay], Bool)
materializeRosterWindowMutation scope =
    withRosterWindowMutationLock scope $
        materializeRosterWindow scope

ensureRosterWeekExistsMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO (Either Text (LiveMutationResult (RosterWeek, Bool)))
ensureRosterWeekExistsMutation scope = do
    materialized <- withRosterWindowMutationLock scope do
        venueConfig <- fetchVenueConfig
        calendarError <- requestRosterCalendarRevisionError venueConfig
        case calendarError of
            Just message -> pure (Left message)
            Nothing      -> Right <$> materializeRosterWindow scope
    case materialized of
        Left message -> pure (Left message)
        Right (days, wasCreated) -> do
            rosterWeek <- legacyPlanningRosterWeekForScope scope False
            let result = (rosterWeek, wasCreated)
            let touchedResources = rosterWeekStructuralTouchedResources scope
            let mutationResult = liveMutationResult result touchedResources
            Right <$>
                if wasCreated
                    then invalidateTouchedResources "roster.week.ensure" mutationResult
                    else pure mutationResult

copyRosterWindowFromSourceMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    ShiftCopyOccurrenceSelections ->
    Id RosterGroup ->
    Day ->
    Day ->
    IO (Either RosterWeekCopyError (LiveMutationResult ()))
copyRosterWindowFromSourceMutation selections rosterGroupId sourceStart targetStart = do
    venueConfig <- fetchVenueConfig
    let targetScope = RosterWindowScope
            { rosterWindowVenueId = currentVenueId
            , rosterWindowRosterGroupId = rosterGroupId
            , rosterWindowStart = targetStart
            , rosterWindowEnd = addDays 7 targetStart
            , rosterWindowCalendarRevision = venueConfig.rosterCalendarRevision
            }
    copyResult <- withRosterWindowMutationLock targetScope do
        lockedVenueConfig <- fetchVenueConfig
        calendarError <- requestRosterCalendarRevisionError lockedVenueConfig
        case calendarError of
            Just message -> pure (Left (RosterWeekCopyPersistenceError message))
            Nothing -> do
                targetWindow <- fetchRosterWindow currentVenueId rosterGroupId targetStart
                let targetHasPublishedDay = any (maybe False ((== Published) . (.publicationState)) . (.persistedRosterDay)) targetWindow.rosterWindowProjectedDays
                if targetHasPublishedDay
                    then pure (Left (RosterWeekCopyPersistenceError "Published roster windows are read-only. Return it to Draft before copying."))
                    else copyRosterWindowByDates selections currentVenueId rosterGroupId sourceStart targetStart
    traverse (\() -> do
        invalidateTouchedResources "roster.window.copy" (liveMutationResult () (rosterWeekStructuralTouchedResources targetScope))) copyResult

toggleRosterWeekLiveStatusMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterWeek -> Bool -> IO (Either Text (LiveMutationResult RosterWeek))
toggleRosterWeekLiveStatusMutation scope rosterWeek nextLiveStatus = do
    result <- withRosterWindowMutationLock scope do
        venueConfig <- fetchVenueConfig
        calendarError <- requestRosterCalendarRevisionError venueConfig
        case calendarError of
            Just message -> pure (Left message)
            Nothing -> do
                let windowStartDate = scope.rosterWindowStart
                when (not nextLiveStatus) do
                    when (unpackId rosterWeek.id /= UUID.nil) do
                        _ <- rosterWeek |> set #isLive False |> updateRecord
                        pure ()
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
                (pure (rosterWeekLiveStatusTouchedResources scope))
            pure (Right mutationResult)

withRosterWindowMutationLock :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO value -> IO value
withRosterWindowMutationLock scope =
    withRosterWindowDateLock
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
appendRosterWindowLaneMutation scope laneName = do
    result <- withRosterWindowMutationLock scope do
        draftRosterWindowErrorUnderLock scope >>= \case
            Just message -> pure (Left message)
            Nothing -> appendRosterWindowLane scope laneName
    traverse (\lane -> invalidateRosterMutation "roster.lane.append" lane (pure (rosterSlotsStructureTouchedResources scope))) result

removeRosterWindowLaneMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Id RosterLane -> IO (Either Text (LiveMutationResult ()))
removeRosterWindowLaneMutation scope laneId = do
    result <- withRosterWindowMutationLock scope do
        draftRosterWindowErrorUnderLock scope >>= \case
            Just message -> pure (Left message)
            Nothing -> removeRosterWindowLane scope laneId currentUser.id
    traverse (\() -> invalidateRosterMutation "roster.lane.remove" () (pure (rosterSlotsStructureTouchedResources scope))) result

repackRosterWindowMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO (Either Text (LiveMutationResult ()))
repackRosterWindowMutation scope = do
    result <- withRosterWindowMutationLock scope do
        draftRosterWindowErrorUnderLock scope >>= \case
            Just message -> pure (Left message)
            Nothing -> repackRosterWindow scope >> pure (Right ())
    traverse (\() -> invalidateRosterMutation "roster.window.repack" () (pure (rosterSlotsStructureTouchedResources scope))) result

toggleRosterDayClosedMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> Bool -> Int -> IO (Either Text (LiveMutationResult RosterDay))
toggleRosterDayClosedMutation scope rosterDay nextClosedState minimumRows = do
    result <- withRosterWindowMutationLock scope do
        draftRosterWindowErrorUnderLock scope >>= \case
            Just message -> pure (Left message)
            Nothing -> do
                currentDay <- fetch rosterDay.id
                when nextClosedState do
                    ensureRosterDayHasMinimumRows currentDay scope.rosterWindowRosterGroupId minimumRows
                Right <$> (currentDay |> set #isClosed nextClosedState |> updateRecord)
    traverse (\updatedDay -> invalidateRosterMutation "roster.day.closed" updatedDay (pure (rosterDayTouchedResources scope rosterDay))) result

addRosterDayRowMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> IO (Either Text (LiveMutationResult RosterDay))
addRosterDayRowMutation scope rosterDay = do
    result <- withRosterWindowMutationLock scope do
        draftRosterWindowErrorUnderLock scope >>= \case
            Just message -> pure (Left message)
            Nothing -> do
                currentDay <- fetch rosterDay.id
                Right <$> (currentDay |> set #rowCount (currentDay.rowCount + 1) |> updateRecord)
    traverse (\updatedDay -> invalidateRosterMutation "roster.day.row_add" updatedDay (pure (rosterDayTouchedResources scope rosterDay))) result

removeRosterDayRowByLanesMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> IO (Either Text (LiveMutationResult ()))
removeRosterDayRowByLanesMutation scope rosterDay = do
    result <- withRosterWindowMutationLock scope do
        draftRosterWindowErrorUnderLock scope >>= \case
            Just message -> pure (Left message)
            Nothing -> removeRosterDayRowByLanes rosterDay currentUser.id >> pure (Right ())
    traverse (\() -> invalidateRosterMutation "roster.row.remove" () (pure (rosterDayTouchedResources scope rosterDay))) result

withRosterSlotStaffLocks :: (?modelContext :: ModelContext) => [RosterSlot] -> IO (Either Text result) -> IO (Either Text result)
withRosterSlotStaffLocks rosterSlots action = do
    let staffIds = nub (mapMaybe (.staffId) rosterSlots)
    maybeResult <- withStaffOperationalLocks staffIds action
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
saveRosterSlotMutation scope rosterDay existingSlot newSlot = do
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
            mutationResult <- invalidateRosterMutation "roster.slot.save" (RosterSlotMutationResult (Just persistedSlot) Nothing False) (rosterSlotMutationTouchedResources scope rosterDay (Just persistedSlot))
            pure (Right mutationResult)

moveRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> RosterDay -> RosterSlot -> RosterSlot -> IO (Either Text (LiveMutationResult RosterSlotMutationResult))
moveRosterSlotMutation scope sourceRosterDay targetRosterDay originalSlot updatedSlot = do
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
            mutationResult <- invalidateTouchedResources "roster.slot.move" $
                liveMutationResult
                    RosterSlotMutationResult
                        { rosterSlotMutationSlot = Just persistedSlot
                        , rosterSlotMutationPreviousStaffId = previousStaffId
                        , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged
                        }
                    (nub (sourceResources <> targetResources))
            pure (Right mutationResult)

updateRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> RosterSlot -> RosterSlot -> Bool -> IO (Either Text (LiveMutationResult RosterSlotMutationResult))
updateRosterSlotMutation scope rosterDay originalSlot updatedSlot allowPublishedOpenFill = do
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
            mutationResult <- invalidateRosterMutation
                "roster.slot.update"
                RosterSlotMutationResult
                    { rosterSlotMutationSlot = Just persistedSlot
                    , rosterSlotMutationPreviousStaffId = previousStaffId
                    , rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged
                    }
                (rosterSlotMutationTouchedResources scope rosterDay (Just persistedSlot))
            pure (Right mutationResult)


deleteRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> RosterSlot -> IO (Either Text (LiveMutationResult RosterSlotMutationResult))
deleteRosterSlotMutation scope rosterDay rosterSlot = do
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
            mutationResult <- invalidateRosterMutation
                "roster.slot.delete"
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

rosterWeekLiveStatusTouchedResources :: RosterWindowScope -> [SurfaceResourceValue]
rosterWeekLiveStatusTouchedResources scope =
    rosterWeekStructuralTouchedResources scope <> timesheetWeekTouchedResources scope

rosterSlotMutationTouchedResources :: RosterWindowScope -> RosterDay -> Maybe RosterSlot -> IO [SurfaceResourceValue]
rosterSlotMutationTouchedResources scope rosterDay maybeSlot = do
    let rosterResources = rosterSlotTouchedResources scope rosterDay maybeSlot
    pure (rosterResources <> timesheetWeekTouchedResources scope)

timesheetWeekTouchedResources :: RosterWindowScope -> [SurfaceResourceValue]
timesheetWeekTouchedResources scope =
    [timesheetWeekResource (unpackId scope.rosterWindowVenueId) scope.rosterWindowStart scope.rosterWindowEnd]

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

module Web.RosterWeeks.Service
    ( copyRosterSlotToDay
    , copyRosterWindowByDates
    , ensureRosterDayHasMinimumRows
    , fetchCurrentRosterWeekOffset
    , fetchActiveStaffForCurrentVenue
    , rosterSlotCopyAmbiguousEndpoints
    , resolveRosterTimelineTargetBoundaries
    , rosterSlotTimesheetSourceChanged
    , rosterWindowCopyAmbiguousEndpoints
    , RosterWeekCopyError (..)
    , publishRequiredFieldsMessage
    , rosterSlotBlocksPublish
    , rosterSlotHasValidStartEnd
    , validateRosterDaysCanPublish
    , validateRosterSlotForPersistence
    , validateRosterSlotsForPersistence
    ) where

import qualified Application.Helper.RosterAwardDuration as RosterAwardDuration
import Application.Helper.TimeRules (authoritativeRosterIntervalIsOperationallyValid)
import Application.PayAssignment
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          copyRosterShiftAssignment,
                                          rosterShiftAssignment,
                                          rosterShiftIsStaffAssigned)
import Application.Staff.Mutations (withStaffOperationalLocksInCurrentTransaction)
import Application.VenueTime (RepeatedTimeOccurrence)
import Application.VenueTime.Model
import Control.Monad (void)
import Data.Either (isRight)
import Data.List (nub)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing, mapMaybe)
import Data.Time (NominalDiffTime, UTCTime, addUTCTime, getCurrentTime, utctDay)
import qualified Data.Time.Calendar as Calendar
import Data.Time.LocalTime (TimeOfDay (..))
import Data.Traversable (traverse)
import Web.Controller.Prelude
import Web.RosterWeeks.Dom (closedRosterDayRows, minimumOpenRosterRows)

fetchCurrentRosterWeekOffset :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
fetchCurrentRosterWeekOffset = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    pure (venueWeekOffsetForDay venueConfig today)

fetchActiveStaffForCurrentVenue :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id Staff -> IO (Maybe Staff)
fetchActiveStaffForCurrentVenue staffId =
    fetchOneOrNothing $ query @Staff
        |> filterWhere (#id, staffId)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)

rosterSlotTimesheetSourceChanged :: RosterSlot -> RosterSlot -> Bool
rosterSlotTimesheetSourceChanged previous next =
    previous.assignmentState /= next.assignmentState
        || previous.staffId /= next.staffId
        || previous.startsAt /= next.startsAt
        || previous.endsAt /= next.endsAt
        || previous.timezone /= next.timezone
        || previous.shiftTypeId /= next.shiftTypeId

copyRosterSlotToDay :: VenueConfig -> RosterWeek -> RosterDay -> RosterWeek -> RosterDay -> ShiftCopyOccurrenceSelections -> RosterSlot -> Either BoundaryModelError RosterSlot
copyRosterSlotToDay venueConfig sourceWeek sourceDay targetWeek targetDay selections slot = do
    let sourceRosterDate = Calendar.addDays (toInteger sourceDay.dayOffset) (venueWeekStartDate venueConfig sourceWeek.weekOffset)
        targetRosterDate = Calendar.addDays (toInteger targetDay.dayOffset) (venueWeekStartDate venueConfig targetWeek.weekOffset)
    (copiedStartsAt, copiedEndsAt) <- copyRosterSlotBoundariesToDate venueConfig sourceRosterDate targetRosterDate selections slot
    pure $
        slot
            |> set #startsAt copiedStartsAt
            |> set #endsAt copiedEndsAt
            |> set #timezone venueConfig.timezone

copyRosterSlotBoundariesToDate :: VenueConfig -> Day -> Day -> ShiftCopyOccurrenceSelections -> RosterSlot -> Either BoundaryModelError (Maybe UTCTime, Maybe UTCTime)
copyRosterSlotBoundariesToDate venueConfig sourceRosterDate targetRosterDate selections slot =
    case (slot.startsAt, slot.endsAt) of
        (Just startsAt, Just endsAt) -> do
            source <- authoritativeBoundariesFromInstants slot.timezone startsAt endsAt Nothing Nothing
            let sourceStartDate = (authoritativeStartLocalTime source).localDay
                targetStartDate = Calendar.addDays (Calendar.diffDays sourceStartDate sourceRosterDate) targetRosterDate
            copied <- copyAuthoritativeBoundariesToDate targetStartDate selections source
            pure (Just (authoritativeStartsAt copied), Just (authoritativeEndsAt copied))
        (maybeStart, maybeEnd) -> do
            copiedStart <- traverse (copySingle selections.copyShiftStartOccurrence) maybeStart
            copiedEnd <- traverse (copySingle selections.copyShiftEndOccurrence) maybeEnd
            pure (copiedStart, copiedEnd)
  where
    copySingle occurrence instant =
        let localTime = storedInstantLocalTime slot.timezone instant
            targetDate = Calendar.addDays (Calendar.diffDays localTime.localDay sourceRosterDate) targetRosterDate
            targetOccurrence = if civilBoundaryIsRepeated targetDate localTime.localTimeOfDay then occurrence else Nothing
         in resolveBoundaryInstant venueConfig.timezone targetDate localTime.localTimeOfDay targetOccurrence

rosterSlotCopyAmbiguousEndpoints :: VenueConfig -> RosterWeek -> RosterDay -> RosterWeek -> RosterDay -> RosterSlot -> (Bool, Bool)
rosterSlotCopyAmbiguousEndpoints venueConfig sourceWeek sourceDay targetWeek targetDay slot =
    (endpointIsRepeated slot.startsAt, endpointIsRepeated slot.endsAt)
  where
    sourceRosterDate = Calendar.addDays (toInteger sourceDay.dayOffset) (venueWeekStartDate venueConfig sourceWeek.weekOffset)
    targetRosterDate = Calendar.addDays (toInteger targetDay.dayOffset) (venueWeekStartDate venueConfig targetWeek.weekOffset)
    endpointIsRepeated maybeInstant = fromMaybe False do
        instant <- maybeInstant
        let localTime = storedInstantLocalTime slot.timezone instant
            targetDate = Calendar.addDays (Calendar.diffDays localTime.localDay sourceRosterDate) targetRosterDate
        pure (civilBoundaryIsRepeated targetDate localTime.localTimeOfDay)

resolveRosterTimelineTargetBoundaries :: Text -> NominalDiffTime -> Day -> TimeOfDay -> Maybe RepeatedTimeOccurrence -> Either BoundaryModelError AuthoritativeBoundaries
resolveRosterTimelineTargetBoundaries timezone duration targetDate targetStartTime targetStartOccurrence = do
    startsAt <- resolveBoundaryInstant timezone targetDate targetStartTime targetStartOccurrence
    authoritativeBoundariesFromInstants timezone startsAt (addUTCTime duration startsAt) Nothing Nothing

data RosterSlotCopyPlan = RosterSlotCopyPlan
    { copiedSourceSlot :: !RosterSlot
    , copiedDayOffset  :: !Int
    , copiedStartsAt   :: !(Maybe UTCTime)
    , copiedEndsAt     :: !(Maybe UTCTime)
    , copiedTimezone   :: !Text
    }

data RosterWeekCopyError
    = RosterWeekCopyBoundaryError !BoundaryModelError
    | RosterWeekCopyPersistenceError !Text
    deriving (Eq, Show)

validateRosterDaysCanPublish :: (?modelContext :: ModelContext) => Id Venue -> [RosterDay] -> IO (Maybe Text)
validateRosterDaysCanPublish venueId rosterDays = do
    rosterSlots <-
        if null rosterDays
            then pure []
            else query @RosterSlot
                |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                |> filterWhere (#deletedAt, Nothing)
                |> fetch
    let blockingSlots = filter rosterSlotBlocksPublish rosterSlots
    if not (null blockingSlots)
        then pure (Just publishRequiredFieldsMessage)
        else validateRosterSlotsForPersistence venueId rosterSlots

publishRequiredFieldsMessage :: Text
publishRequiredFieldsMessage = "Roster window cannot be Published until every shift has a start time, valid end time, and shift type."

rosterSlotBlocksPublish :: RosterSlot -> Bool
rosterSlotBlocksPublish slot =
    isNothing slot.startsAt
        || isNothing slot.shiftTypeId
        || not (rosterSlotHasValidStartEnd slot)

rosterSlotHasValidStartEnd :: RosterSlot -> Bool
rosterSlotHasValidStartEnd slot =
    case (slot.startsAt, slot.endsAt) of
        (Just startsAt, Just endsAt) ->
            either
                (const False)
                authoritativeRosterIntervalIsOperationallyValid
                (authoritativeBoundariesFromInstants slot.timezone startsAt endsAt Nothing Nothing)
        _ -> False

rosterPayConfigurationMessage :: Text
rosterPayConfigurationMessage = "Resolve pay configuration for the selected staff member or shift type before saving this roster shift."

rosterSlotRequiredFieldsMessage :: Text
rosterSlotRequiredFieldsMessage = "Choose a staff member, valid start/end times, and a shift type before saving this roster shift."

validateRosterSlotForPersistence :: (?modelContext :: ModelContext) => Id Venue -> RosterSlot -> IO (Maybe Text)
validateRosterSlotForPersistence venueId slot
    | isNothing slot.shiftTypeId || not (rosterSlotHasValidStartEnd slot) =
        pure (Just rosterSlotRequiredFieldsMessage)
    | otherwise =
        case rosterShiftAssignment slot of
            Left _ -> pure (Just rosterSlotRequiredFieldsMessage)
            Right OpenAssignment -> pure Nothing
            Right StaffAssignment {} -> do
                disposition <- resolveRosterSlotPayDisposition venueId slot
                case disposition of
                    Left message -> pure (Just message)
                    Right EffectiveRosterOnly -> pure Nothing
                    Right _ -> do
                        maybeStaff <- case slot.staffId of
                            Just staffId -> query @Staff |> filterWhere (#id, Id staffId) |> fetchOneOrNothing
                            Nothing      -> pure Nothing
                        pure do
                            staff <- maybeStaff
                            violation <- rosterSlotAwardDurationViolation staff slot
                            pure (RosterAwardDuration.rosterAwardDurationViolationMessage violation)

validateRosterSlotsForPersistence :: (?modelContext :: ModelContext) => Id Venue -> [RosterSlot] -> IO (Maybe Text)
validateRosterSlotsForPersistence venueId slots =
    firstJustM (map (validateRosterSlotForPersistence venueId) slots)

resolveRosterSlotPayDisposition :: (?modelContext :: ModelContext) => Id Venue -> RosterSlot -> IO (Either Text EffectivePayAssignment)
resolveRosterSlotPayDisposition venueId slot = do
    maybeStaff <- case slot.staffId of
        Just staffId -> query @Staff |> filterWhere (#id, Id staffId) |> fetchOneOrNothing
        Nothing      -> pure Nothing
    maybeShiftType <- case slot.shiftTypeId of
        Just shiftTypeId -> query @ShiftType |> filterWhere (#id, Id shiftTypeId) |> fetchOneOrNothing
        Nothing          -> pure Nothing
    case (maybeStaff, maybeShiftType) of
        (Just staff, Just shiftType)
            | staffIsAvailable venueId staff && shiftTypeIsAvailable venueId shiftType -> do
                activeAwardIds <- fetchActiveReferencedAwardIds staff shiftType
                activeXeroIds <- fetchActiveReferencedXeroIds venueId staff shiftType
                let staffAssignment = StaffPayAssignment staff.payAssignmentMode staff.defaultAwardLevelId staff.importedXeroPayItemId
                    shiftAssignment = ShiftPayAssignment shiftType.payAssignmentMode shiftType.overrideAwardLevelId shiftType.importedXeroPayItemId
                    referencesAvailable =
                        not (staffPayAssignmentRequiresRemediation activeAwardIds activeXeroIds staffAssignment)
                            && not (shiftPayAssignmentRequiresRemediation activeAwardIds activeXeroIds shiftAssignment)
                pure case (referencesAvailable, resolvePayAssignment staffAssignment shiftAssignment) of
                    (True, effective@EffectiveAwardRate {}) -> Right effective
                    (True, effective@EffectiveXeroRate {}) -> Right effective
                    (True, EffectiveRosterOnly) -> Right EffectiveRosterOnly
                    _ -> Left rosterPayConfigurationMessage
        _ -> pure (Left rosterPayConfigurationMessage)

staffIsAvailable :: Id Venue -> Staff -> Bool
staffIsAvailable venueId staff =
    staff.venueId == unpackId venueId && staff.isActive && isNothing staff.archivedAt

shiftTypeIsAvailable :: Id Venue -> ShiftType -> Bool
shiftTypeIsAvailable venueId shiftType =
    shiftType.venueId == unpackId venueId && shiftType.isActive && isNothing shiftType.archivedAt

fetchActiveReferencedAwardIds :: (?modelContext :: ModelContext) => Staff -> ShiftType -> IO [Id AwardLevel]
fetchActiveReferencedAwardIds staff shiftType = do
    let ids = nub (catMaybes [staff.defaultAwardLevelId, shiftType.overrideAwardLevelId])
    if null ids
        then pure []
        else map (.id) <$> (query @AwardLevel |> filterWhereIn (#id, ids) |> filterWhere (#isActive, True) |> fetch)

fetchActiveReferencedXeroIds :: (?modelContext :: ModelContext) => Id Venue -> Staff -> ShiftType -> IO [Id XeroImportedPayItem]
fetchActiveReferencedXeroIds venueId staff shiftType = do
    let ids = nub (catMaybes [staff.importedXeroPayItemId, shiftType.importedXeroPayItemId])
    if null ids
        then pure []
        else map (.id) <$> (query @XeroImportedPayItem |> filterWhereIn (#id, ids) |> filterWhere (#venueId, unpackId venueId) |> filterWhere (#archivedAt, Nothing) |> filterWhere (#providerAvailable, True) |> fetch)

rosterSlotAwardDurationViolation :: Staff -> RosterSlot -> Maybe RosterAwardDuration.RosterAwardDurationViolation
rosterSlotAwardDurationViolation staff slot = do
    startsAt <- slot.startsAt
    endsAt <- slot.endsAt
    boundaries <- either (const Nothing) Just (authoritativeBoundariesFromInstants slot.timezone startsAt endsAt Nothing Nothing)
    RosterAwardDuration.rosterAwardDurationViolation staff.employmentBasis boundaries

firstJustM :: Monad m => [m (Maybe value)] -> m (Maybe value)
firstJustM [] = pure Nothing
firstJustM (action : remaining) = do
    result <- action
    maybe (firstJustM remaining) (pure . Just) result

data RosterWindowSlotCopyPlan = RosterWindowSlotCopyPlan
    { windowCopiedSourceSlot :: !RosterSlot
    , windowCopiedTargetDate :: !Day
    , windowCopiedStartsAt   :: !(Maybe UTCTime)
    , windowCopiedEndsAt     :: !(Maybe UTCTime)
    }

copyRosterWindowByDates ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    ShiftCopyOccurrenceSelections ->
    Id Venue ->
    Id RosterGroup ->
    Day ->
    Day ->
    IO (Either RosterWeekCopyError ())
copyRosterWindowByDates selections venueId rosterGroupId sourceStart targetStart = do
    venueConfig <- fetchVenueConfig
    sourceDays <- fetchWindowDays venueId rosterGroupId sourceStart
    targetDays <- fetchWindowDays venueId rosterGroupId targetStart
    let sourceDayById = Map.fromList [(unpackId day.id, day) | day <- sourceDays]
    sourceSlots <- fetchActiveSlotsForDays sourceDays
    let prepare sourceSlot = do
            sourceDay <- maybe (Left (BoundaryUnsupportedTimezone "missing roster day")) Right (Map.lookup sourceSlot.rosterDayId sourceDayById)
            let targetDate = Calendar.addDays (Calendar.diffDays sourceDay.operationalDate sourceStart) targetStart
            (startsAt, endsAt) <- copyRosterSlotBoundariesToDate venueConfig sourceDay.operationalDate targetDate selections sourceSlot
            pure RosterWindowSlotCopyPlan
                { windowCopiedSourceSlot = sourceSlot
                , windowCopiedTargetDate = targetDate
                , windowCopiedStartsAt = startsAt
                , windowCopiedEndsAt = endsAt
                }
    case traverse prepare (filter rosterSlotHasData sourceSlots) of
        Left failure -> pure (Left (RosterWeekCopyBoundaryError failure))
        Right plans -> do
            let legacyPlans =
                    [ RosterSlotCopyPlan plan.windowCopiedSourceSlot
                        (fromInteger (Calendar.diffDays plan.windowCopiedTargetDate targetStart))
                        plan.windowCopiedStartsAt
                        plan.windowCopiedEndsAt
                        venueConfig.timezone
                    | plan <- plans
                    ]
            validation <- validateRosterWeekCopyPersistence venueId legacyPlans
            case validation of
                Left failure -> pure (Left failure)
                Right () -> withValidatedRosterWeekCopyStaff venueId legacyPlans do
                    now <- getCurrentTime
                    forM_ targetDays \day -> do
                        activeSlots <- query @RosterSlot
                            |> filterWhere (#rosterDayId, unpackId day.id)
                            |> filterWhere (#deletedAt, Nothing)
                            |> fetch
                        forM_ activeSlots \slot -> void (slot |> set #deletedAt (Just now) |> set #deleteReason (Just "roster_window_replaced") |> updateRecord)
                        activeLanes <- query @RosterLane |> filterWhere (#rosterDayId, unpackId day.id) |> filterWhere (#deletedAt, Nothing) |> fetch
                        forM_ activeLanes \lane -> void (lane |> set #deletedAt (Just now) |> set #deleteReason (Just "roster_window_replaced") |> updateRecord)
                    targetDaysByDate <- materializeCopyTargetDays venueId rosterGroupId sourceStart targetStart sourceDays targetDays
                    sourceLanes <- if null sourceDays then pure [] else query @RosterLane
                        |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) sourceDays)
                        |> filterWhere (#deletedAt, Nothing)
                        |> fetch
                    let sourceLaneById = Map.fromList [(unpackId lane.id, lane) | lane <- sourceLanes]
                    targetLaneBySource <- fmap Map.fromList $ forM sourceLanes \sourceLane -> do
                        sourceDay <- maybe (fail "Roster copy source lane lost its day") pure (Map.lookup sourceLane.rosterDayId sourceDayById)
                        let targetDate = Calendar.addDays (Calendar.diffDays sourceDay.operationalDate sourceStart) targetStart
                        targetDay <- maybe (fail "Roster copy target day missing") pure (Map.lookup targetDate targetDaysByDate)
                        targetLane <- newRecord @RosterLane
                            |> set #rosterDayId (unpackId targetDay.id)
                            |> set #legacyRosterWeekSlotDefinitionId Nothing
                            |> set #name sourceLane.name
                            |> set #sortOrder sourceLane.sortOrder
                            |> createRecord
                        pure (unpackId sourceLane.id, targetLane)
                    forM_ plans \plan -> do
                        sourceLane <- maybe (fail "Roster copy source lane missing") pure (Map.lookup plan.windowCopiedSourceSlot.rosterLaneId sourceLaneById)
                        targetLane <- maybe (fail "Roster copy target lane missing") pure (Map.lookup (unpackId sourceLane.id) targetLaneBySource)
                        targetDay <- maybe (fail "Roster copy target date missing") pure (Map.lookup plan.windowCopiedTargetDate targetDaysByDate)
                        conflictingSlots <- query @RosterSlot
                            |> filterWhere (#rosterDayId, unpackId targetDay.id)
                            |> filterWhere (#rosterLaneId, unpackId targetLane.id)
                            |> filterWhere (#rowIndex, plan.windowCopiedSourceSlot.rowIndex)
                            |> filterWhere (#deletedAt, Nothing)
                            |> fetch
                        forM_ conflictingSlots \conflictingSlot ->
                            void (conflictingSlot |> set #deletedAt (Just now) |> set #deleteReason (Just "roster_window_replaced") |> updateRecord)
                        case copyRosterShiftAssignment plan.windowCopiedSourceSlot (newRecord @RosterSlot) of
                            Left message -> fail (cs message)
                            Right copied -> void $
                                copied
                                    |> set #rosterDayId (unpackId targetDay.id)
                                    |> set #rosterLaneId (unpackId targetLane.id)
                                    |> set #rosterWeekSlotDefinitionId Nothing
                                    |> set #slotSortOrder targetLane.sortOrder
                                    |> set #rowIndex plan.windowCopiedSourceSlot.rowIndex
                                    |> set #startsAt plan.windowCopiedStartsAt
                                    |> set #endsAt plan.windowCopiedEndsAt
                                    |> set #timezone venueConfig.timezone
                                    |> set #shiftTypeId plan.windowCopiedSourceSlot.shiftTypeId
                                    |> createRecord
                    pure (Right ())

fetchWindowDays :: (?modelContext :: ModelContext) => Id Venue -> Id RosterGroup -> Day -> IO [RosterDay]
fetchWindowDays venueId rosterGroupId windowStart =
    query @RosterDay
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> filterWhereGreaterThanOrEqualTo (#operationalDate, windowStart)
        |> filterWhereLessThan (#operationalDate, Calendar.addDays 7 windowStart)
        |> orderByAsc #operationalDate
        |> fetch

fetchActiveSlotsForDays :: (?modelContext :: ModelContext) => [RosterDay] -> IO [RosterSlot]
fetchActiveSlotsForDays [] = pure []
fetchActiveSlotsForDays days = query @RosterSlot
    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) days)
    |> filterWhere (#deletedAt, Nothing)
    |> fetch

materializeCopyTargetDays ::
    (?modelContext :: ModelContext) =>
    Id Venue -> Id RosterGroup -> Day -> Day -> [RosterDay] -> [RosterDay] -> IO (Map.Map Day RosterDay)
materializeCopyTargetDays venueId rosterGroupId sourceStart targetStart sourceDays existingTargetDays = do
    let sourceByDate = Map.fromList [(day.operationalDate, day) | day <- sourceDays]
    existingOrCreated <- forM [0 .. 6] \dayOffset -> do
        let sourceDate = Calendar.addDays dayOffset sourceStart
        let targetDate = Calendar.addDays dayOffset targetStart
        let sourceDay = Map.lookup sourceDate sourceByDate
        case find ((== targetDate) . (.operationalDate)) existingTargetDays of
            Just targetDay -> targetDay
                |> set #publicationState Draft
                |> set #isClosed (maybe False (.isClosed) sourceDay)
                |> set #rowCount (maybe 4 (.rowCount) sourceDay)
                |> updateRecord
            Nothing -> newRecord @RosterDay
                |> set #rosterWeekId Nothing
                |> set #venueId (unpackId venueId)
                |> set #rosterGroupId (unpackId rosterGroupId)
                |> set #operationalDate targetDate
                |> set #publicationState Draft
                |> set #dayOffset (fromInteger dayOffset)
                |> set #isClosed (maybe False (.isClosed) sourceDay)
                |> set #rowCount (maybe 4 (.rowCount) sourceDay)
                |> createRecord
    pure (Map.fromList [(day.operationalDate, day) | day <- existingOrCreated])

rosterWindowCopyAmbiguousEndpoints :: (?modelContext :: ModelContext) => VenueConfig -> Id Venue -> Id RosterGroup -> Day -> Day -> IO (Bool, Bool)
rosterWindowCopyAmbiguousEndpoints venueConfig venueId rosterGroupId sourceStart targetStart = do
    sourceDays <- fetchWindowDays venueId rosterGroupId sourceStart
    sourceSlots <- fetchActiveSlotsForDays sourceDays
    let sourceDayById = Map.fromList [(unpackId day.id, day) | day <- sourceDays]
        endpointIsRepeated selectInstant slot = do
            sourceDay <- Map.lookup slot.rosterDayId sourceDayById
            instant <- selectInstant slot
            let localTime = storedInstantLocalTime slot.timezone instant
                targetRosterDate = Calendar.addDays (Calendar.diffDays sourceDay.operationalDate sourceStart) targetStart
                targetDate = Calendar.addDays (Calendar.diffDays localTime.localDay sourceDay.operationalDate) targetRosterDate
            pure (civilBoundaryIsRepeated targetDate localTime.localTimeOfDay)
    pure
        ( any (fromMaybe False . endpointIsRepeated (.startsAt)) sourceSlots
        , any (fromMaybe False . endpointIsRepeated (.endsAt)) sourceSlots
        )

ensureRosterDayHasMinimumRows :: (?modelContext :: ModelContext) => RosterDay -> Id RosterGroup -> Int -> IO ()
ensureRosterDayHasMinimumRows rosterDay _rosterGroupId minimumRowCount = do
    when (rosterDay.rowCount < minimumRowCount) do
        _ <- rosterDay
            |> set #rowCount minimumRowCount
            |> updateRecord
        pure ()

withValidatedRosterWeekCopyStaff :: (?modelContext :: ModelContext) => Id Venue -> [RosterSlotCopyPlan] -> IO (Either RosterWeekCopyError value) -> IO (Either RosterWeekCopyError value)
withValidatedRosterWeekCopyStaff venueId plans action = do
    let staffIds = nub (mapMaybe ((.staffId) . (.copiedSourceSlot)) plans)
    maybeResult <- withStaffOperationalLocksInCurrentTransaction staffIds do
        validation <- validateRosterWeekCopyPersistence venueId plans
        case validation of
            Left failure -> pure (Left failure)
            Right ()     -> action
    pure (fromMaybe (Left (RosterWeekCopyPersistenceError "A copied staff member is no longer available for rostering.")) maybeResult)

validateRosterWeekCopyPersistence :: (?modelContext :: ModelContext) => Id Venue -> [RosterSlotCopyPlan] -> IO (Either RosterWeekCopyError ())
validateRosterWeekCopyPersistence venueId = go
  where
    go [] = pure (Right ())
    go (plan : remainingPlans) = do
        let candidate =
                plan.copiedSourceSlot
                    |> set #startsAt plan.copiedStartsAt
                    |> set #endsAt plan.copiedEndsAt
                    |> set #timezone plan.copiedTimezone
        validationError <- validateRosterSlotForPersistence venueId candidate
        case validationError of
            Just message -> pure (Left (RosterWeekCopyPersistenceError message))
            Nothing      -> go remainingPlans

rosterSlotHasData :: RosterSlot -> Bool
rosterSlotHasData slot =
    isRight (rosterShiftAssignment slot)
        || isJust slot.startsAt
        || isJust slot.endsAt
        || isJust slot.shiftTypeId


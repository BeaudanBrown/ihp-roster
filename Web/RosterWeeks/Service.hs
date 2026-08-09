module Web.RosterWeeks.Service
    ( RosterWeekSlotTemplate
    , appendRosterWeekSlotDefinition
    , copyRosterSlotToDay
    , copyRosterWeek
    , createEmptyRosterWeek
    , deleteRosterWeekSlotDefinition
    , ensureRosterDayHasMinimumRows
    , ensureRosterWeekExists
    , fetchRosterWeekSlotTemplate
    , fetchCurrentRosterWeekOffset
    , fetchActiveRosterWeekSlotDefinitions
    , fetchActiveStaffForCurrentVenue
    , fetchRosterWeekOrderedSlotNames
    , previewRemoveRosterRowPacking
    , replaceRosterWeekFromSource
    , removeRosterRowWithPacking
    , repackRosterWeekDays
    , rosterSlotHasData
    , rosterSlotCopyAmbiguousEndpoints
    , resolveRosterTimelineTargetBoundaries
    , rosterSlotTimesheetSourceChanged
    , rosterWeekCopyAmbiguousEndpoints
    , RemoveRosterRowPackingPreview (..)
    , RosterWeekCopyError (..)
    , publishRequiredFieldsMessage
    , rosterSlotBlocksPublish
    , rosterSlotHasValidStartEnd
    , validateRosterSlotForPersistence
    , validateRosterSlotsForPersistence
    , validateRosterWeekCanGoLive
    ) where

import qualified Application.Helper.RosterAwardDuration as RosterAwardDuration
import Application.Helper.RosterGroups
import Application.Helper.TimeRules (authoritativeRosterIntervalIsOperationallyValid)
import Application.PayAssignment
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          copyRosterShiftAssignment,
                                          rosterShiftAssignment,
                                          rosterShiftIsStaffAssigned)
import Application.Staff.Mutations (withStaffOperationalLocksInCurrentTransaction)
import Application.VenueTime (RepeatedTimeOccurrence)
import Application.VenueTime.Model
import Data.Coerce (coerce)
import Data.Either (isRight)
import Data.List (nub, sort, sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing, listToMaybe,
                   mapMaybe)
import qualified Data.Text as Text
import Data.Time (NominalDiffTime, UTCTime, addUTCTime, getCurrentTime, utctDay)
import qualified Data.Time.Calendar as Calendar
import Data.Time.LocalTime (TimeOfDay (..))
import Data.Traversable (traverse)
import Data.UUID (UUID)
import qualified Database.PostgreSQL.Simple as PG
import IHP.ModelSupport (sqlExecDiscardResult)
import Web.Controller.Prelude
import Web.RosterWeeks.Dom (closedRosterDayRows, minimumOpenRosterRows)

data RemoveRosterRowPackingPreview = RemoveRosterRowPackingPreview
    { removeRosterRowLastRowIndex     :: !Int
    , removeRosterRowOverflowCount    :: !Int
    , removeRosterRowDeletedDataCount :: !Int
    }

data RosterSlotPlacement = RosterSlotPlacement
    { rosterSlotPlacementSlot       :: !RosterSlot
    , rosterSlotPlacementDefinition :: !RosterWeekSlotDefinition
    , rosterSlotPlacementRowIndex   :: !Int
    }

data RemoveRosterRowPackingPlan = RemoveRosterRowPackingPlan
    { removeRosterRowPlanLastRowIndex  :: !Int
    , removeRosterRowPlanPlacements    :: ![RosterSlotPlacement]
    , removeRosterRowPlanOverflowSlots :: ![RosterSlot]
    , removeRosterRowPlanDeleteSlots   :: ![RosterSlot]
    , removeRosterRowPlanTargetKeys    :: ![(UUID, Int)]
    , removeRosterRowPlanActiveDefIds  :: ![UUID]
    }

fetchCurrentRosterWeekOffset :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
fetchCurrentRosterWeekOffset = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    pure (venueWeekOffsetForDay venueConfig today)

type RosterWeekSlotTemplate = (RosterWeekSlotDefinition, Int)

fetchRosterWeekSlotTemplate :: (?modelContext :: ModelContext) => RosterWeek -> IO [RosterWeekSlotTemplate]
fetchRosterWeekSlotTemplate rosterWeek = do
    slotDefinitions <- fetchActiveRosterWeekSlotDefinitions rosterWeek
    pure (map (\slotDefinition -> (slotDefinition, slotDefinition.sortOrder)) slotDefinitions)


fetchRosterWeekOrderedSlotNames :: (?modelContext :: ModelContext) => RosterWeek -> IO [RosterWeekSlotDefinition]
fetchRosterWeekOrderedSlotNames rosterWeek =
    map fst <$> fetchRosterWeekSlotTemplate rosterWeek


fetchActiveStaffForCurrentVenue :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id Staff -> IO (Maybe Staff)
fetchActiveStaffForCurrentVenue staffId =
    fetchOneOrNothing $ query @Staff
        |> filterWhere (#id, staffId)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)

fetchActiveRosterWeekSlotDefinitions :: (?modelContext :: ModelContext) => RosterWeek -> IO [RosterWeekSlotDefinition]
fetchActiveRosterWeekSlotDefinitions rosterWeek =
    query @RosterWeekSlotDefinition
        |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
        |> filterWhere (#deletedAt, Nothing)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch

ensureRosterWeekExists :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO (RosterWeek, Bool)
ensureRosterWeekExists rosterGroupId weekOffset = do
    existing <- query @RosterWeek
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> filterWhere (#weekOffset, weekOffset)
        |> fetchOneOrNothing
    case existing of
        Just rosterWeek -> pure (rosterWeek, False)
        Nothing -> do
            rosterWeek <- createEmptyRosterWeek rosterGroupId weekOffset
            pure (rosterWeek, True)

createEmptyRosterWeek :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO RosterWeek
createEmptyRosterWeek rosterGroupId weekOffset = do
    rosterWeek <- newRecord @RosterWeek
        |> set #venueId (unpackId currentVenueId)
        |> set #rosterGroupId (unpackId rosterGroupId)
        |> set #weekOffset weekOffset
        |> set #isLive False
        |> createRecord

    sqlExecDiscardResult
        "INSERT INTO roster_days (roster_week_id, day_offset, is_closed) \
        \SELECT ?, day_offsets.day_offset, FALSE \
        \FROM generate_series(0, 6) AS day_offsets(day_offset)"
        (PG.Only (unpackId rosterWeek.id))

    createInitialRosterWeekSlotDefinitions rosterWeek

    pure rosterWeek

createInitialRosterWeekSlotDefinitions :: (?modelContext :: ModelContext) => RosterWeek -> IO ()
createInitialRosterWeekSlotDefinitions rosterWeek = do
    previousWeek <- query @RosterWeek
        |> filterWhere (#rosterGroupId, rosterWeek.rosterGroupId)
        |> filterWhereLessThan (#weekOffset, rosterWeek.weekOffset)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByDesc #weekOffset
        |> fetchOneOrNothing
    sourceDefinitions <-
        case previousWeek of
            Just sourceWeek -> fetchActiveRosterWeekSlotDefinitions sourceWeek
            Nothing         -> pure []
    if null sourceDefinitions
        then do
            rosterGroupSlotNames <- fetchActiveRosterGroupSlotNames (Id rosterWeek.rosterGroupId)
            let slotTemplates =
                    if null rosterGroupSlotNames
                        then zip defaultRosterSlotNames [0 :: Int ..]
                        else map (\slotName -> (slotName.name, slotName.sortOrder)) rosterGroupSlotNames
            forM_ slotTemplates \(slotName, sortOrder) -> do
                _ <- newRecord @RosterWeekSlotDefinition
                    |> set #rosterWeekId (unpackId rosterWeek.id)
                    |> set #name slotName
                    |> set #sortOrder sortOrder
                    |> createRecord
                pure ()
        else forM_ sourceDefinitions \sourceDefinition -> do
            _ <- newRecord @RosterWeekSlotDefinition
                |> set #rosterWeekId (unpackId rosterWeek.id)
                |> set #name sourceDefinition.name
                |> set #sortOrder sourceDefinition.sortOrder
                |> createRecord
            pure ()

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

validateRosterWeekCanGoLive :: (?modelContext :: ModelContext) => RosterWeek -> Bool -> IO (Maybe Text)
validateRosterWeekCanGoLive _ False = pure Nothing
validateRosterWeekCanGoLive rosterWeek True = do
    rosterDays <- query @RosterDay
        |> filterWhere (#rosterWeekId, Just (unpackId rosterWeek.id))
        |> fetch
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
        else validateRosterSlotsForPersistence (Id rosterWeek.venueId) rosterSlots

publishRequiredFieldsMessage :: Text
publishRequiredFieldsMessage = "Roster week cannot go live until every shift has a start time, valid end time, and shift type."

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

copyRosterWeek :: (?context :: ControllerContext, ?modelContext :: ModelContext) => ShiftCopyOccurrenceSelections -> RosterWeek -> Int -> IO (Either RosterWeekCopyError RosterWeek)
copyRosterWeek selections sourceWeek targetWeekOffset = do
    venueConfig <- fetchVenueConfig
    prepared <- prepareRosterWeekCopyForPersistence venueConfig selections sourceWeek targetWeekOffset
    case prepared of
        Left failure -> pure (Left failure)
        Right plans -> withValidatedRosterWeekCopyStaff (Id sourceWeek.venueId) plans do
            targetWeek <- newRecord @RosterWeek
                |> set #venueId (unpackId currentVenueId)
                |> set #rosterGroupId sourceWeek.rosterGroupId
                |> set #weekOffset targetWeekOffset
                |> set #isLive False
                |> createRecord

            sqlExecDiscardResult
                "INSERT INTO roster_days (roster_week_id, day_offset, is_closed, row_count) \
                \SELECT ?, day_offsets.day_offset, COALESCE(source_days.is_closed, FALSE), COALESCE(source_days.row_count, 4) \
                \FROM generate_series(0, 6) AS day_offsets(day_offset) \
                \LEFT JOIN roster_days source_days \
                \    ON source_days.roster_week_id = ? \
                \    AND source_days.day_offset = day_offsets.day_offset \
                \ORDER BY day_offsets.day_offset"
                (unpackId targetWeek.id, unpackId sourceWeek.id)

            copyRosterWeekSlotDefinitionsAndSlots sourceWeek targetWeek plans
            pure (Right targetWeek)

replaceRosterWeekFromSource :: (?context :: ControllerContext, ?modelContext :: ModelContext) => ShiftCopyOccurrenceSelections -> RosterWeek -> RosterWeek -> IO (Either RosterWeekCopyError RosterWeek)
replaceRosterWeekFromSource selections sourceWeek targetWeek = do
    venueConfig <- fetchVenueConfig
    prepared <- prepareRosterWeekCopyForPersistence venueConfig selections sourceWeek targetWeek.weekOffset
    case prepared of
        Left failure -> pure (Left failure)
        Right plans -> withValidatedRosterWeekCopyStaff (Id sourceWeek.venueId) plans do
            _ <- targetWeek
                |> set #isLive False
                |> updateRecord

            sqlExecDiscardResult
                "UPDATE roster_week_slot_definitions \
                \SET deleted_at = NOW(), delete_reason = 'roster_week_replaced', updated_at = NOW() \
                \WHERE roster_week_id = ? \
                \AND deleted_at IS NULL"
                (PG.Only (unpackId targetWeek.id))

            sqlExecDiscardResult
                "UPDATE roster_slots \
                \SET deleted_at = NOW(), delete_reason = 'roster_week_replaced', updated_at = NOW() \
                \FROM roster_days \
                \WHERE roster_slots.roster_day_id = roster_days.id \
                \AND roster_days.roster_week_id = ? \
                \AND roster_slots.deleted_at IS NULL"
                (PG.Only (unpackId targetWeek.id))

            sqlExecDiscardResult
                "UPDATE roster_days AS target_days \
                \SET is_closed = source_days.is_closed, row_count = source_days.row_count, updated_at = NOW() \
                \FROM roster_days AS source_days \
                \WHERE target_days.roster_week_id = ? \
                \AND source_days.roster_week_id = ? \
                \AND target_days.day_offset = source_days.day_offset"
                (unpackId targetWeek.id, unpackId sourceWeek.id)

            copyRosterWeekSlotDefinitionsAndSlots sourceWeek targetWeek plans
            Right <$> fetch targetWeek.id

ensureRosterDayHasMinimumRows :: (?modelContext :: ModelContext) => RosterDay -> Id RosterGroup -> Int -> IO ()
ensureRosterDayHasMinimumRows rosterDay _rosterGroupId minimumRowCount = do
    when (rosterDay.rowCount < minimumRowCount) do
        _ <- rosterDay
            |> set #rowCount minimumRowCount
            |> updateRecord
        pure ()

rosterWeekCopyAmbiguousEndpoints :: (?modelContext :: ModelContext) => VenueConfig -> RosterWeek -> Int -> IO (Bool, Bool)
rosterWeekCopyAmbiguousEndpoints venueConfig sourceWeek targetWeekOffset = do
    sourceDays <- query @RosterDay |> filterWhere (#rosterWeekId, Just (unpackId sourceWeek.id)) |> fetch
    sourceSlots <-
        if null sourceDays
            then pure []
            else query @RosterSlot
                |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) sourceDays)
                |> filterWhere (#deletedAt, Nothing)
                |> fetch
    let sourceDayById = Map.fromList [(unpackId day.id, day) | day <- sourceDays]
        sourceWeekStart = venueWeekStartDate venueConfig sourceWeek.weekOffset
        targetWeekStart = venueWeekStartDate venueConfig targetWeekOffset
        endpointIsRepeated selectInstant slot = do
            sourceDay <- Map.lookup slot.rosterDayId sourceDayById
            instant <- selectInstant slot
            let sourceRosterDate = Calendar.addDays (toInteger sourceDay.dayOffset) sourceWeekStart
                targetRosterDate = Calendar.addDays (toInteger sourceDay.dayOffset) targetWeekStart
                localTime = storedInstantLocalTime slot.timezone instant
                targetDate = Calendar.addDays (Calendar.diffDays localTime.localDay sourceRosterDate) targetRosterDate
            pure (civilBoundaryIsRepeated targetDate localTime.localTimeOfDay)
    pure
        ( any (fromMaybe False . endpointIsRepeated (.startsAt)) sourceSlots
        , any (fromMaybe False . endpointIsRepeated (.endsAt)) sourceSlots
        )

prepareRosterWeekCopy :: (?modelContext :: ModelContext) => VenueConfig -> ShiftCopyOccurrenceSelections -> RosterWeek -> Int -> IO (Either BoundaryModelError [RosterSlotCopyPlan])
prepareRosterWeekCopy venueConfig selections sourceWeek targetWeekOffset = do
    sourceDays <-
        query @RosterDay
            |> filterWhere (#rosterWeekId, Just (unpackId sourceWeek.id))
            |> fetch
    let sourceDayById = Map.fromList [(unpackId day.id, day) | day <- sourceDays]
    sourceSlots <-
        if null sourceDays
            then pure []
            else query @RosterSlot
                |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) sourceDays)
                |> filterWhere (#deletedAt, Nothing)
                |> fetch
    pure (traverse (copySlot sourceDayById) (filter rosterSlotHasData sourceSlots))
  where
    sourceWeekStart = venueWeekStartDate venueConfig sourceWeek.weekOffset
    targetWeekStart = venueWeekStartDate venueConfig targetWeekOffset

    copySlot sourceDayById sourceSlot = do
        sourceDay <- maybe (Left (BoundaryUnsupportedTimezone "missing roster day")) Right (Map.lookup sourceSlot.rosterDayId sourceDayById)
        let sourceRosterDate = Calendar.addDays (toInteger sourceDay.dayOffset) sourceWeekStart
            targetRosterDate = Calendar.addDays (toInteger sourceDay.dayOffset) targetWeekStart
        (startsAt, endsAt) <- copyRosterSlotBoundariesToDate venueConfig sourceRosterDate targetRosterDate selections sourceSlot
        pure RosterSlotCopyPlan
            { copiedSourceSlot = sourceSlot
            , copiedDayOffset = sourceDay.dayOffset
            , copiedStartsAt = startsAt
            , copiedEndsAt = endsAt
            , copiedTimezone = venueConfig.timezone
            }

withValidatedRosterWeekCopyStaff :: (?modelContext :: ModelContext) => Id Venue -> [RosterSlotCopyPlan] -> IO (Either RosterWeekCopyError value) -> IO (Either RosterWeekCopyError value)
withValidatedRosterWeekCopyStaff venueId plans action = do
    let staffIds = nub (mapMaybe ((.staffId) . (.copiedSourceSlot)) plans)
    maybeResult <- withStaffOperationalLocksInCurrentTransaction staffIds do
        validation <- validateRosterWeekCopyPersistence venueId plans
        case validation of
            Left failure -> pure (Left failure)
            Right ()     -> action
    pure (fromMaybe (Left (RosterWeekCopyPersistenceError "A copied staff member is no longer available for rostering.")) maybeResult)

prepareRosterWeekCopyForPersistence :: (?modelContext :: ModelContext) => VenueConfig -> ShiftCopyOccurrenceSelections -> RosterWeek -> Int -> IO (Either RosterWeekCopyError [RosterSlotCopyPlan])
prepareRosterWeekCopyForPersistence venueConfig selections sourceWeek targetWeekOffset = do
    prepared <- prepareRosterWeekCopy venueConfig selections sourceWeek targetWeekOffset
    case prepared of
        Left failure -> pure (Left (RosterWeekCopyBoundaryError failure))
        Right plans -> do
            validation <- validateRosterWeekCopyPersistence (Id sourceWeek.venueId) plans
            pure (plans <$ validation)

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

copyRosterWeekSlotDefinitionsAndSlots :: (?modelContext :: ModelContext) => RosterWeek -> RosterWeek -> [RosterSlotCopyPlan] -> IO ()
copyRosterWeekSlotDefinitionsAndSlots sourceWeek targetWeek plans = do
    sourceDefinitions <- fetchActiveRosterWeekSlotDefinitions sourceWeek
    targetDefinitions <- forM sourceDefinitions \sourceDefinition ->
        newRecord @RosterWeekSlotDefinition
            |> set #rosterWeekId (unpackId targetWeek.id)
            |> set #name sourceDefinition.name
            |> set #sortOrder sourceDefinition.sortOrder
            |> createRecord
    targetDays <-
        query @RosterDay
            |> filterWhere (#rosterWeekId, Just (unpackId targetWeek.id))
            |> fetch
    let targetDayByOffset = Map.fromList [(day.dayOffset, day) | day <- targetDays]
        sourceDefinitionById = Map.fromList [(unpackId definition.id, definition) | definition <- sourceDefinitions]
        targetDefinitionByKey = Map.fromList [((definition.name, definition.sortOrder), definition) | definition <- targetDefinitions]
    forM_ plans \plan -> do
        let sourceSlot = plan.copiedSourceSlot
        case do
            targetDay <- Map.lookup plan.copiedDayOffset targetDayByOffset
            sourceDefinitionId <- sourceSlot.rosterWeekSlotDefinitionId
            sourceDefinition <- Map.lookup sourceDefinitionId sourceDefinitionById
            targetDefinition <- Map.lookup (sourceDefinition.name, sourceDefinition.sortOrder) targetDefinitionByKey
            pure (targetDay, targetDefinition)
          of
            Nothing -> error "Roster week copy plan no longer matches target structure"
            Just (targetDay, targetDefinition) ->
                case copyRosterShiftAssignment sourceSlot (newRecord @RosterSlot) of
                    Left message -> error message
                    Right assignmentSlot -> do
                        _ <- assignmentSlot
                            |> set #rosterDayId (unpackId targetDay.id)
                            |> set #rosterWeekSlotDefinitionId (Just (unpackId targetDefinition.id))
                            |> set #slotSortOrder targetDefinition.sortOrder
                            |> set #rowIndex sourceSlot.rowIndex
                            |> set #startsAt plan.copiedStartsAt
                            |> set #endsAt plan.copiedEndsAt
                            |> set #timezone plan.copiedTimezone
                            |> set #shiftTypeId sourceSlot.shiftTypeId
                            |> createRecord
                        pure ()

appendRosterWeekSlotDefinition :: (?modelContext :: ModelContext) => RosterWeek -> Text -> IO RosterWeekSlotDefinition
appendRosterWeekSlotDefinition rosterWeek slotName = do
    existingDefinitions <- fetchActiveRosterWeekSlotDefinitions rosterWeek
    let nextSortOrder = maybe 0 ((+ 1) . (.sortOrder)) (last existingDefinitions)
    newRecord @RosterWeekSlotDefinition
        |> set #rosterWeekId (unpackId rosterWeek.id)
        |> set #name slotName
        |> set #sortOrder nextSortOrder
        |> createRecord


rosterSlotHasData :: RosterSlot -> Bool
rosterSlotHasData slot =
    isRight (rosterShiftAssignment slot)
        || isJust slot.startsAt
        || isJust slot.endsAt
        || isJust slot.shiftTypeId

previewRemoveRosterRowPacking :: (?modelContext :: ModelContext) => RosterDay -> [RosterWeekSlotDefinition] -> IO RemoveRosterRowPackingPreview
previewRemoveRosterRowPacking rosterDay activeDefinitions = do
    activeSlots <- fetchActiveSlotsForDay rosterDay
    let plan = buildRemoveRosterRowPackingPlan rosterDay activeDefinitions activeSlots
    pure RemoveRosterRowPackingPreview
        { removeRosterRowLastRowIndex = removeRosterRowPlanLastRowIndex plan
        , removeRosterRowOverflowCount = length (removeRosterRowPlanOverflowSlots plan)
        , removeRosterRowDeletedDataCount = length (filter rosterSlotHasData (removeRosterRowPlanDeleteSlots plan))
        }

removeRosterRowWithPacking :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterDay -> [RosterWeekSlotDefinition] -> IO ()
removeRosterRowWithPacking rosterDay activeDefinitions = do
    activeSlots <- fetchActiveSlotsForDay rosterDay
    let plan = buildRemoveRosterRowPackingPlan rosterDay activeDefinitions activeSlots
    temporarilyMoveDataSlots activeSlots (map rosterSlotPlacementSlot (removeRosterRowPlanPlacements plan)) 1
    softDeleteRemoveRosterRowSlots plan activeSlots
    forM_ (removeRosterRowPlanPlacements plan) \placement -> do
        _ <- rosterSlotPlacementSlot placement
            |> set #rosterWeekSlotDefinitionId (Just (unpackId (get #id (rosterSlotPlacementDefinition placement))))
            |> set #slotSortOrder (rosterSlotPlacementDefinition placement).sortOrder
            |> set #rowIndex (rosterSlotPlacementRowIndex placement)
            |> updateRecord
        pure ()
    _ <- rosterDay
        |> set #rowCount (max 0 (rosterDay.rowCount - 1))
        |> updateRecord
    pure ()

buildRemoveRosterRowPackingPlan :: RosterDay -> [RosterWeekSlotDefinition] -> [RosterSlot] -> RemoveRosterRowPackingPlan
buildRemoveRosterRowPackingPlan rosterDay activeDefinitions activeSlots =
    RemoveRosterRowPackingPlan
        { removeRosterRowPlanLastRowIndex = lastRowIndex
        , removeRosterRowPlanPlacements = retainedPlacements <> incomingPlacements
        , removeRosterRowPlanOverflowSlots = overflowSlots
        , removeRosterRowPlanDeleteSlots = deletedRowSlots
        , removeRosterRowPlanTargetKeys = map (\placement -> (unpackId (get #id (rosterSlotPlacementDefinition placement)), rosterSlotPlacementRowIndex placement)) (retainedPlacements <> incomingPlacements)
        , removeRosterRowPlanActiveDefIds = activeDefinitionIds
        }
    where
        activeDefinitionIds = map (unpackId . (.id)) activeDefinitions
        activeTemplateSlots = filter (\slot -> slot.rosterWeekSlotDefinitionId `elem` map Just activeDefinitionIds) activeSlots
        lastRowIndex = rosterDay.rowCount - 1
        targetRowCount = max 0 lastRowIndex
        deletedRowSlots =
            filter (\slot -> slot.rowIndex == lastRowIndex && slot.rosterWeekSlotDefinitionId `elem` map Just activeDefinitionIds) activeTemplateSlots
        incomingSlots =
            sortOn (definitionOrderKey activeDefinitions) (filter rosterSlotHasData deletedRowSlots)
        retainedPlacements =
            concatMap retainedPlacementsForDefinition activeDefinitions
        freeCells =
            concatMap freeCellsForDefinition activeDefinitions
        incomingPlacements =
            zipWith
                (\slot (slotDefinition, rowIndex) -> RosterSlotPlacement slot slotDefinition rowIndex)
                incomingSlots
                freeCells
        overflowSlots = drop (length freeCells) incomingSlots
        retainedPlacementsForDefinition slotDefinition =
            zipWith
                (\rowIndex slot -> RosterSlotPlacement slot slotDefinition rowIndex)
                [0 ..]
                (retainedDataSlotsForDefinition slotDefinition)
        retainedDataSlotsForDefinition slotDefinition =
            activeTemplateSlots
                |> filter (\slot -> slot.rowIndex < lastRowIndex && slot.rosterWeekSlotDefinitionId == Just (unpackId slotDefinition.id) && rosterSlotHasData slot)
                |> sortOn (.rowIndex)
        freeCellsForDefinition slotDefinition =
            let retainedCount = length (retainedDataSlotsForDefinition slotDefinition)
             in [ (slotDefinition, rowIndex)
                | rowIndex <- [retainedCount .. targetRowCount - 1]
                ]

definitionOrderKey :: [RosterWeekSlotDefinition] -> RosterSlot -> (Int, Int, UTCTime, Id RosterSlot)
definitionOrderKey activeDefinitions slot =
    ( maybe slot.slotSortOrder (\definitionId -> Map.findWithDefault slot.slotSortOrder definitionId definitionSortOrderById) slot.rosterWeekSlotDefinitionId
    , slot.rowIndex
    , slot.createdAt
    , slot.id
    )
    where
        definitionSortOrderById =
            Map.fromList
                [ (unpackId slotDefinition.id, slotDefinition.sortOrder)
                | slotDefinition <- activeDefinitions
                ]

softDeleteRemoveRosterRowSlots :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RemoveRosterRowPackingPlan -> [RosterSlot] -> IO ()
softDeleteRemoveRosterRowSlots plan activeSlots = do
    now <- getCurrentTime
    let placementSlotIds = map (unpackId . get #id . rosterSlotPlacementSlot) (removeRosterRowPlanPlacements plan)
    let overflowSlotIds = map (unpackId . get #id) (removeRosterRowPlanOverflowSlots plan)
    let activeDefinitionIds = removeRosterRowPlanActiveDefIds plan
    let lastRowIndex = removeRosterRowPlanLastRowIndex plan
    let shouldDelete slot =
            unpackId slot.id `elem` overflowSlotIds
                || ( slot.rosterWeekSlotDefinitionId `elem` map Just activeDefinitionIds
                    && slot.rowIndex >= lastRowIndex
                    && unpackId slot.id `notElem` placementSlotIds
                   )
                || not (rosterSlotHasData slot)
    forM_ (filter shouldDelete activeSlots) \slot -> do
        _ <- slot
            |> set #deletedAt (Just now)
            |> set #deletedByUserId (Just (unpackId currentUser.id))
            |> set #deleteReason (Just "roster_row_removed")
            |> updateRecord
        pure ()

repackRosterWeekDays :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWeek -> IO ()
repackRosterWeekDays rosterWeek = do
    activeDefinitions <- fetchActiveRosterWeekSlotDefinitions rosterWeek
    unless (null activeDefinitions) do
        rosterDays <- query @RosterDay
            |> filterWhere (#rosterWeekId, Just (unpackId rosterWeek.id))
            |> orderByAsc #dayOffset
            |> fetch
        forM_ rosterDays (repackRosterDay activeDefinitions)

repackRosterDay :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => [RosterWeekSlotDefinition] -> RosterDay -> IO ()
repackRosterDay activeDefinitions rosterDay = do
    initialSlots <- fetchActiveSlotsForDay rosterDay
    let activeDefinitionIds = map (unpackId . (.id)) activeDefinitions
    let minimumRows =
            if rosterDay.isClosed
                then closedRosterDayRows
                else minimumOpenRosterRows
    let requiredRows =
            max
                minimumRows
                (ceilingDiv (length (filter rosterSlotHasData initialSlots)) (length activeDefinitions))

    _ <- rosterDay
        |> set #rowCount requiredRows
        |> updateRecord
    activeSlots <- fetchActiveSlotsForDay rosterDay
    staffById <- fetchStaffLabelsById activeSlots
    let definitionSortOrderById =
            Map.fromList
                [ (unpackId slotDefinition.id, slotDefinition.sortOrder)
                | slotDefinition <- activeDefinitions
                ]
    let dataSlots = sortOn (slotPackingKey definitionSortOrderById staffById) (filter rosterSlotHasData activeSlots)
    let targetCells =
            [ (slotDefinition, rowIndex)
            | slotDefinition <- activeDefinitions
            , rowIndex <- [0 .. requiredRows - 1]
            ]
    let placements = zip dataSlots targetCells

    temporarilyMoveDataSlots activeSlots dataSlots requiredRows
    softDeleteDisplacedBlankSlots activeDefinitionIds (map snd placements) activeSlots
    forM_ placements \(slot, (slotDefinition, rowIndex)) -> do
        _ <- slot
            |> set #rosterWeekSlotDefinitionId (Just (unpackId slotDefinition.id))
            |> set #slotSortOrder slotDefinition.sortOrder
            |> set #rowIndex rowIndex
            |> updateRecord
        pure ()

fetchActiveSlotsForDay :: (?modelContext :: ModelContext) => RosterDay -> IO [RosterSlot]
fetchActiveSlotsForDay rosterDay =
    query @RosterSlot
        |> filterWhere (#rosterDayId, unpackId rosterDay.id)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch

fetchStaffLabelsById :: (?modelContext :: ModelContext) => [RosterSlot] -> IO (Map.Map UUID Text)
fetchStaffLabelsById slots = do
    let staffIds = nub (mapMaybe (.staffId) (filter rosterShiftIsStaffAssigned slots))
    if null staffIds
        then pure Map.empty
        else do
            staffMembers <- query @Staff
                |> filterWhereIn (#id, map Id staffIds)
                |> fetch
            pure (Map.fromList (map (\staff -> (unpackId staff.id, staffSortLabel staff)) staffMembers))

staffSortLabel :: Staff -> Text
staffSortLabel staff =
    Text.toCaseFold (fromMaybe staff.firstName staff.preferredName <> " " <> staff.lastName)

slotPackingKey :: Map.Map UUID Int -> Map.Map UUID Text -> RosterSlot -> (Bool, TimeOfDay, Text, Int, Int, UTCTime, Id RosterSlot)
slotPackingKey definitionSortOrderById staffById slot =
    ( isNothing slot.startsAt
    , fromMaybe (TimeOfDay 23 59 59) (rosterSlotStartTime slot)
    , fromMaybe "\xffff" (slot.staffId >>= (`Map.lookup` staffById))
    , slot.rowIndex
    , maybe slot.slotSortOrder (\definitionId -> Map.findWithDefault slot.slotSortOrder definitionId definitionSortOrderById) slot.rosterWeekSlotDefinitionId
    , slot.createdAt
    , slot.id
    )

temporarilyMoveDataSlots :: (?modelContext :: ModelContext) => [RosterSlot] -> [RosterSlot] -> Int -> IO ()
temporarilyMoveDataSlots activeSlots dataSlots requiredRows = do
    let maxExistingRowIndex = fromMaybe 0 (nonEmptyMaximum (map (.rowIndex) activeSlots))
    let temporaryRowStart = maxExistingRowIndex + requiredRows + length dataSlots + 100
    forM_ (zip [0 :: Int ..] dataSlots) \(index, slot) -> do
        _ <- slot
            |> set #rowIndex (temporaryRowStart + index)
            |> updateRecord
        pure ()

nonEmptyMaximum :: Ord a => [a] -> Maybe a
nonEmptyMaximum []     = Nothing
nonEmptyMaximum values = Just (maximum values)

softDeleteDisplacedBlankSlots :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => [UUID] -> [(RosterWeekSlotDefinition, Int)] -> [RosterSlot] -> IO ()
softDeleteDisplacedBlankSlots activeDefinitionIds _ activeSlots = do
    now <- getCurrentTime
    let shouldDelete slot =
            not (rosterSlotHasData slot)
                && slot.rosterWeekSlotDefinitionId `notElem` map Just activeDefinitionIds
    forM_ (filter shouldDelete activeSlots) \slot -> do
        _ <- slot
            |> set #deletedAt (Just now)
            |> set #deletedByUserId (Just (unpackId currentUser.id))
            |> set #deleteReason (Just "roster_slots_repacked")
            |> updateRecord
        pure ()

ceilingDiv :: Int -> Int -> Int
ceilingDiv _ 0 = 0
ceilingDiv numerator denominator =
    (numerator + denominator - 1) `div` denominator

deleteRosterWeekSlotDefinition :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWeekSlotDefinition -> IO ()
deleteRosterWeekSlotDefinition slotDefinition = do
    now <- getCurrentTime
    _ <- slotDefinition
        |> set #deletedAt (Just now)
        |> set #deletedByUserId (Just (unpackId currentUser.id))
        |> set #deleteReason (Just "roster_slot_definition_removed")
        |> updateRecord
    rosterWeek <- fetch (Id slotDefinition.rosterWeekId :: Id RosterWeek)
    repackRosterWeekDays rosterWeek

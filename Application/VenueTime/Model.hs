module Application.VenueTime.Model
    ( BoundaryModelError (..)
    , TimesheetIntegrityError (..)
    , ValidatedTimesheetTiming
    , decodeTimesheetTiming
    , timesheetTimingBoundaries
    , timesheetTimingWorkedOn
    , timesheetTimingStartTime
    , timesheetTimingEndTime
    , timesheetTimingBreakStartTime
    , timesheetTimingBreakEndTime
    , timesheetTimingBreakElapsedSeconds
    , timesheetTimingElapsedSeconds
    , timesheetTimingPaidElapsedSeconds
    , RosterShiftIntegrityError (..)
    , ValidatedRosterShiftTiming
    , decodeRosterShiftTiming
    , rosterShiftTimingBoundaries
    , rosterShiftTimingStartTime
    , rosterShiftTimingEndTime
    , rosterShiftTimingElapsedSeconds
    , rosterShiftTimingStartOccurrence
    , rosterShiftTimingEndOccurrence
    , recoverStoredInstantLocalTime
    , recoverStoredInstantOccurrence
    , validatePersistedTimezone
    , BreakBoundaryInput (..)
    , ShiftBoundaryInput (..)
    , ShiftCopyOccurrenceSelections (..)
    , noShiftCopyOccurrenceSelections
    , AuthoritativeBoundaries
    , resolveShiftBoundaries
    , resolveBoundaryInstant
    , authoritativeBoundariesFromInstants
    , copyAuthoritativeBoundariesToDate
    , authoritativeStartsAt
    , authoritativeEndsAt
    , authoritativeBreakStartsAt
    , authoritativeBreakEndsAt
    , authoritativeTimezone
    , authoritativeElapsedSeconds
    , authoritativeBreakElapsedSeconds
    , authoritativePaidElapsedSeconds
    , authoritativeAwardSegments
    , authoritativeUnpaidMealBreak
    , authoritativeStartLocalTime
    , authoritativeEndLocalTime
    , authoritativeBreakStartLocalTime
    , authoritativeBreakEndLocalTime
    , authoritativeStartOccurrence
    , authoritativeEndOccurrence
    , authoritativeBreakStartOccurrence
    , authoritativeBreakEndOccurrence
    , applyTimesheetEntryBoundaries
    , applyRosterSlotBoundaries
    , timesheetEntryBoundaries
    , timesheetEntryOperationalDate
    , timesheetEntryWorkedOn
    , timesheetEntryStartTime
    , timesheetEntryEndTime
    , timesheetEntryHadBreak
    , timesheetEntryBreakStartTime
    , timesheetEntryBreakEndTime
    , timesheetEntryBreakElapsedSeconds
    , timesheetEntryElapsedSeconds
    , timesheetEntryPaidElapsedSeconds
    , rosterSlotStartTime
    , rosterSlotEndTime
    , rosterSlotElapsedSeconds
    , rosterSlotStartOccurrence
    , rosterSlotEndOccurrence
    , occurrenceParamValue
    , parseOccurrenceParam
    , civilBoundaryIsRepeated
    , repeatedEndpointPairCanShareDate
    , storedInstantLocalTime
    , storedInstantOccurrence
    ) where

import Application.VenueTime
import Data.Time.Calendar (addDays, diffDays)
import Data.Time.Clock (NominalDiffTime, UTCTime)
import Data.Time.LocalTime (LocalTime (..), TimeOfDay, midnight)
import Data.Traversable (traverse)
import Generated.Types
import IHP.HaskellSupport (set)
import IHP.Prelude

mapLeft :: (left -> mappedLeft) -> Either left value -> Either mappedLeft value
mapLeft transform = either (Left . transform) Right

-- | Integration errors stay typed at the form/model boundary. The pure
-- 'Application.VenueTime' errors are retained without string parsing.
data BoundaryModelError
    = BoundaryCivilTimeError !VenueTimeError
    | BoundaryUnsupportedTimezone !Text
    | BoundaryBreakNotContained
    | BoundaryBreakShapeInvalid
    | BoundaryShiftShapeInvalid
    deriving (Eq, Show)

data TimesheetIntegrityError
    = TimesheetTimingInvalid !BoundaryModelError
    deriving (Eq, Show)

newtype ValidatedTimesheetTiming = ValidatedTimesheetTiming AuthoritativeBoundaries
    deriving (Eq, Show)

newtype RosterShiftIntegrityError
    = RosterShiftTimingInvalid BoundaryModelError
    deriving (Eq, Show)

newtype ValidatedRosterShiftTiming = ValidatedRosterShiftTiming AuthoritativeBoundaries
    deriving (Eq, Show)

data BreakBoundaryInput = BreakBoundaryInput
    { breakBoundaryStartTime       :: !TimeOfDay
    , breakBoundaryStartOccurrence :: !(Maybe RepeatedTimeOccurrence)
    , breakBoundaryEndTime         :: !TimeOfDay
    , breakBoundaryEndOccurrence   :: !(Maybe RepeatedTimeOccurrence)
    }
    deriving (Eq, Show)

data ShiftBoundaryInput = ShiftBoundaryInput
    { shiftBoundaryDate            :: !Day
    , shiftBoundaryStartTime       :: !TimeOfDay
    , shiftBoundaryStartOccurrence :: !(Maybe RepeatedTimeOccurrence)
    , shiftBoundaryEndTime         :: !TimeOfDay
    , shiftBoundaryEndOccurrence   :: !(Maybe RepeatedTimeOccurrence)
    , shiftBoundaryBreak           :: !(Maybe BreakBoundaryInput)
    }
    deriving (Eq, Show)

data ShiftCopyOccurrenceSelections = ShiftCopyOccurrenceSelections
    { copyShiftStartOccurrence      :: !(Maybe RepeatedTimeOccurrence)
    , copyShiftEndOccurrence        :: !(Maybe RepeatedTimeOccurrence)
    , copyShiftBreakStartOccurrence :: !(Maybe RepeatedTimeOccurrence)
    , copyShiftBreakEndOccurrence   :: !(Maybe RepeatedTimeOccurrence)
    }
    deriving (Eq, Show)

noShiftCopyOccurrenceSelections :: ShiftCopyOccurrenceSelections
noShiftCopyOccurrenceSelections =
    ShiftCopyOccurrenceSelections
        { copyShiftStartOccurrence = Nothing
        , copyShiftEndOccurrence = Nothing
        , copyShiftBreakStartOccurrence = Nothing
        , copyShiftBreakEndOccurrence = Nothing
        }

data AuthoritativeBoundaries = AuthoritativeBoundaries
    { storedShiftInterval :: !ResolvedInterval
    , storedBreakInterval :: !(Maybe ResolvedInterval)
    , storedTimezone      :: !Text
    }
    deriving (Eq, Show)

resolveBoundaryInstant :: Text -> Day -> TimeOfDay -> Maybe RepeatedTimeOccurrence -> Either BoundaryModelError UTCTime
resolveBoundaryInstant timezone day timeOfDay occurrence = do
    validateTimezone timezone
    resolved <- mapLeft BoundaryCivilTimeError (resolveCivilTime (civilTime day timeOfDay occurrence))
    pure (resolvedInstantUTC resolved)

resolveShiftBoundaries :: Text -> ShiftBoundaryInput -> Either BoundaryModelError AuthoritativeBoundaries
resolveShiftBoundaries timezone input = do
    validateTimezone timezone
    shiftStart <- mapLeft BoundaryCivilTimeError $ resolveCivilTime (civilTime input.shiftBoundaryDate input.shiftBoundaryStartTime input.shiftBoundaryStartOccurrence)
    shiftEnd <- mapLeft BoundaryCivilTimeError $
        resolveOrderedEndpoint
            (>)
            shiftStart
            input.shiftBoundaryDate
            input.shiftBoundaryEndTime
            input.shiftBoundaryEndOccurrence
            (input.shiftBoundaryEndTime > input.shiftBoundaryStartTime)
    shiftInterval <- mapLeft BoundaryCivilTimeError $ resolvedIntervalFromInstants shiftStart shiftEnd
    breakInterval <- traverse (resolveBreak shiftInterval) input.shiftBoundaryBreak
    validateBreakContained shiftInterval breakInterval
    pure AuthoritativeBoundaries
        { storedShiftInterval = shiftInterval
        , storedBreakInterval = breakInterval
        , storedTimezone = timezone
        }
  where
    resolveBreak shiftInterval breakInput =
        mapLeft BoundaryCivilTimeError do
            breakStart <- resolveOrderedEndpoint
                (>=)
                (resolvedIntervalStart shiftInterval)
                input.shiftBoundaryDate
                breakInput.breakBoundaryStartTime
                breakInput.breakBoundaryStartOccurrence
                (breakInput.breakBoundaryStartTime >= input.shiftBoundaryStartTime)
            let breakStartDate = (resolvedInstantLocalTime breakStart).localDay
            breakEnd <- resolveOrderedEndpoint
                (>)
                breakStart
                breakStartDate
                breakInput.breakBoundaryEndTime
                breakInput.breakBoundaryEndOccurrence
                (breakInput.breakBoundaryEndTime > breakInput.breakBoundaryStartTime)
            resolvedIntervalFromInstants breakStart breakEnd

resolveOrderedEndpoint :: (ResolvedInstant -> ResolvedInstant -> Bool) -> ResolvedInstant -> Day -> TimeOfDay -> Maybe RepeatedTimeOccurrence -> Bool -> Either VenueTimeError ResolvedInstant
resolveOrderedEndpoint isOrdered lowerBound baseDate timeOfDay occurrence preferBaseDate =
    case resolveCivilTime (civilTime baseDate timeOfDay occurrence) of
        Right candidate
            | candidate `isOrdered` lowerBound -> Right candidate
            | otherwise -> resolveOnNextDay
        Left failure
            | preferBaseDate -> Left failure
            | otherwise -> resolveOnNextDay
  where
    resolveOnNextDay = resolveCivilTime (civilTime (addDays 1 baseDate) timeOfDay occurrence)

authoritativeBoundariesFromInstants :: Text -> UTCTime -> UTCTime -> Maybe UTCTime -> Maybe UTCTime -> Either BoundaryModelError AuthoritativeBoundaries
authoritativeBoundariesFromInstants timezone startsAt endsAt breakStartsAt breakEndsAt = do
    validateTimezone timezone
    shiftInterval <- intervalFromUTC startsAt endsAt
    breakInterval <- case (breakStartsAt, breakEndsAt) of
        (Nothing, Nothing)     -> Right Nothing
        (Just start, Just end) -> Just <$> intervalFromUTC start end
        _                      -> Left BoundaryBreakShapeInvalid
    validateBreakContained shiftInterval breakInterval
    pure AuthoritativeBoundaries
        { storedShiftInterval = shiftInterval
        , storedBreakInterval = breakInterval
        , storedTimezone = timezone
        }
  where
    intervalFromUTC start end =
        mapLeft BoundaryCivilTimeError $
            resolvedIntervalFromInstants
                (resolvedInstantFromUTC start)
                (resolvedInstantFromUTC end)

copyAuthoritativeBoundariesToDate :: Day -> ShiftCopyOccurrenceSelections -> AuthoritativeBoundaries -> Either BoundaryModelError AuthoritativeBoundaries
copyAuthoritativeBoundariesToDate targetStartDate selections source = do
    validateTimezone source.storedTimezone
    copiedShift <- mapLeft BoundaryCivilTimeError $
        copyIntervalToDate
            targetStartDate
            CopyOccurrenceSelections
                { copiedStartOccurrence = occurrenceOnlyWhenRepeated targetStartDate sourceStartLocal.localTimeOfDay selections.copyShiftStartOccurrence
                , copiedEndOccurrence = occurrenceOnlyWhenRepeated targetEndDate sourceEndLocal.localTimeOfDay selections.copyShiftEndOccurrence
                }
            source.storedShiftInterval
    copiedBreak <- traverse copyBreak source.storedBreakInterval
    validateBreakContained copiedShift copiedBreak
    pure AuthoritativeBoundaries
        { storedShiftInterval = copiedShift
        , storedBreakInterval = copiedBreak
        , storedTimezone = source.storedTimezone
        }
  where
    sourceStartLocal = authoritativeStartLocalTime source
    sourceEndLocal = authoritativeEndLocalTime source
    sourceStartDate = sourceStartLocal.localDay
    targetEndDate = addDays (diffDays sourceEndLocal.localDay sourceStartDate) targetStartDate
    occurrenceOnlyWhenRepeated targetDate targetTime selection
        | civilBoundaryIsRepeated targetDate targetTime = selection
        | otherwise = Nothing
    copyBreak breakInterval =
        mapLeft BoundaryCivilTimeError $
            resolveInterval copiedStart copiedEnd
      where
        breakStartLocal = resolvedInstantLocalTime (resolvedIntervalStart breakInterval)
        breakEndLocal = resolvedInstantLocalTime (resolvedIntervalEnd breakInterval)
        copiedBreakStartDate = addDays (diffDays breakStartLocal.localDay sourceStartDate) targetStartDate
        copiedBreakEndDate = addDays (diffDays breakEndLocal.localDay sourceStartDate) targetStartDate
        copiedStart = civilTime
            copiedBreakStartDate
            breakStartLocal.localTimeOfDay
            (occurrenceOnlyWhenRepeated copiedBreakStartDate breakStartLocal.localTimeOfDay selections.copyShiftBreakStartOccurrence)
        copiedEnd = civilTime
            copiedBreakEndDate
            breakEndLocal.localTimeOfDay
            (occurrenceOnlyWhenRepeated copiedBreakEndDate breakEndLocal.localTimeOfDay selections.copyShiftBreakEndOccurrence)

validateTimezone :: Text -> Either BoundaryModelError ()
validateTimezone timezone
    | timezone == melbourneTimeZoneName = Right ()
    | otherwise = Left (BoundaryUnsupportedTimezone timezone)

validateBreakContained :: ResolvedInterval -> Maybe ResolvedInterval -> Either BoundaryModelError ()
validateBreakContained _ Nothing = Right ()
validateBreakContained shift (Just breakInterval)
    | authoritativeInstant (resolvedIntervalStart breakInterval) < authoritativeInstant (resolvedIntervalStart shift) = Left BoundaryBreakNotContained
    | authoritativeInstant (resolvedIntervalEnd breakInterval) > authoritativeInstant (resolvedIntervalEnd shift) = Left BoundaryBreakNotContained
    | otherwise = Right ()

authoritativeInstant :: ResolvedInstant -> UTCTime
authoritativeInstant = resolvedInstantUTC

authoritativeStartsAt :: AuthoritativeBoundaries -> UTCTime
authoritativeStartsAt = authoritativeInstant . resolvedIntervalStart . (.storedShiftInterval)

authoritativeEndsAt :: AuthoritativeBoundaries -> UTCTime
authoritativeEndsAt = authoritativeInstant . resolvedIntervalEnd . (.storedShiftInterval)

authoritativeBreakStartsAt :: AuthoritativeBoundaries -> Maybe UTCTime
authoritativeBreakStartsAt = fmap (authoritativeInstant . resolvedIntervalStart) . (.storedBreakInterval)

authoritativeBreakEndsAt :: AuthoritativeBoundaries -> Maybe UTCTime
authoritativeBreakEndsAt = fmap (authoritativeInstant . resolvedIntervalEnd) . (.storedBreakInterval)

authoritativeTimezone :: AuthoritativeBoundaries -> Text
authoritativeTimezone = (.storedTimezone)

authoritativeElapsedSeconds :: AuthoritativeBoundaries -> NominalDiffTime
authoritativeElapsedSeconds = resolvedIntervalElapsedSeconds . (.storedShiftInterval)

authoritativeBreakElapsedSeconds :: AuthoritativeBoundaries -> NominalDiffTime
authoritativeBreakElapsedSeconds = maybe 0 resolvedIntervalElapsedSeconds . (.storedBreakInterval)

authoritativePaidElapsedSeconds :: AuthoritativeBoundaries -> NominalDiffTime
authoritativePaidElapsedSeconds boundaries =
    authoritativeElapsedSeconds boundaries - authoritativeBreakElapsedSeconds boundaries

authoritativeAwardSegments :: AuthoritativeBoundaries -> Either BoundaryModelError [AwardSegment]
authoritativeAwardSegments =
    mapLeft BoundaryCivilTimeError . awardSegments . (.storedShiftInterval)

-- | The resolved break is an input fact for wage calculation, not a derived
-- payable segment. Keep it opaque so callers cannot construct civil-time data.
authoritativeUnpaidMealBreak :: AuthoritativeBoundaries -> Maybe ResolvedInterval
authoritativeUnpaidMealBreak = (.storedBreakInterval)

authoritativeStartLocalTime :: AuthoritativeBoundaries -> LocalTime
authoritativeStartLocalTime = resolvedInstantLocalTime . resolvedIntervalStart . (.storedShiftInterval)

authoritativeEndLocalTime :: AuthoritativeBoundaries -> LocalTime
authoritativeEndLocalTime = resolvedInstantLocalTime . resolvedIntervalEnd . (.storedShiftInterval)

authoritativeBreakStartLocalTime :: AuthoritativeBoundaries -> Maybe LocalTime
authoritativeBreakStartLocalTime = fmap (resolvedInstantLocalTime . resolvedIntervalStart) . (.storedBreakInterval)

authoritativeBreakEndLocalTime :: AuthoritativeBoundaries -> Maybe LocalTime
authoritativeBreakEndLocalTime = fmap (resolvedInstantLocalTime . resolvedIntervalEnd) . (.storedBreakInterval)

authoritativeStartOccurrence :: AuthoritativeBoundaries -> Maybe RepeatedTimeOccurrence
authoritativeStartOccurrence = resolvedInstantOccurrence . resolvedIntervalStart . (.storedShiftInterval)

authoritativeEndOccurrence :: AuthoritativeBoundaries -> Maybe RepeatedTimeOccurrence
authoritativeEndOccurrence = resolvedInstantOccurrence . resolvedIntervalEnd . (.storedShiftInterval)

authoritativeBreakStartOccurrence :: AuthoritativeBoundaries -> Maybe RepeatedTimeOccurrence
authoritativeBreakStartOccurrence boundaries =
    boundaries.storedBreakInterval >>= resolvedInstantOccurrence . resolvedIntervalStart

authoritativeBreakEndOccurrence :: AuthoritativeBoundaries -> Maybe RepeatedTimeOccurrence
authoritativeBreakEndOccurrence boundaries =
    boundaries.storedBreakInterval >>= resolvedInstantOccurrence . resolvedIntervalEnd

applyTimesheetEntryBoundaries :: AuthoritativeBoundaries -> TimesheetEntry -> TimesheetEntry
applyTimesheetEntryBoundaries boundaries entry =
    entry
        |> set #startsAt (authoritativeStartsAt boundaries)
        |> set #endsAt (authoritativeEndsAt boundaries)
        |> set #breakStartsAt (authoritativeBreakStartsAt boundaries)
        |> set #breakEndsAt (authoritativeBreakEndsAt boundaries)
        |> set #timezone (authoritativeTimezone boundaries)

applyRosterSlotBoundaries :: AuthoritativeBoundaries -> RosterSlot -> RosterSlot
applyRosterSlotBoundaries boundaries slot =
    slot
        |> set #startsAt (Just (authoritativeStartsAt boundaries))
        |> set #endsAt (Just (authoritativeEndsAt boundaries))
        |> set #timezone (authoritativeTimezone boundaries)

decodeTimesheetTiming :: TimesheetEntry -> Either TimesheetIntegrityError ValidatedTimesheetTiming
decodeTimesheetTiming = mapLeft TimesheetTimingInvalid . fmap ValidatedTimesheetTiming . timesheetEntryBoundaries

timesheetTimingBoundaries :: ValidatedTimesheetTiming -> AuthoritativeBoundaries
timesheetTimingBoundaries (ValidatedTimesheetTiming boundaries) = boundaries

timesheetTimingWorkedOn :: ValidatedTimesheetTiming -> Day
timesheetTimingWorkedOn = (.localDay) . authoritativeStartLocalTime . timesheetTimingBoundaries

timesheetTimingStartTime :: ValidatedTimesheetTiming -> TimeOfDay
timesheetTimingStartTime = (.localTimeOfDay) . authoritativeStartLocalTime . timesheetTimingBoundaries

timesheetTimingEndTime :: ValidatedTimesheetTiming -> TimeOfDay
timesheetTimingEndTime = (.localTimeOfDay) . authoritativeEndLocalTime . timesheetTimingBoundaries

timesheetTimingBreakStartTime :: ValidatedTimesheetTiming -> Maybe TimeOfDay
timesheetTimingBreakStartTime = fmap (.localTimeOfDay) . authoritativeBreakStartLocalTime . timesheetTimingBoundaries

timesheetTimingBreakEndTime :: ValidatedTimesheetTiming -> Maybe TimeOfDay
timesheetTimingBreakEndTime = fmap (.localTimeOfDay) . authoritativeBreakEndLocalTime . timesheetTimingBoundaries

timesheetTimingBreakElapsedSeconds :: ValidatedTimesheetTiming -> NominalDiffTime
timesheetTimingBreakElapsedSeconds = authoritativeBreakElapsedSeconds . timesheetTimingBoundaries

timesheetTimingElapsedSeconds :: ValidatedTimesheetTiming -> NominalDiffTime
timesheetTimingElapsedSeconds = authoritativeElapsedSeconds . timesheetTimingBoundaries

timesheetTimingPaidElapsedSeconds :: ValidatedTimesheetTiming -> NominalDiffTime
timesheetTimingPaidElapsedSeconds = authoritativePaidElapsedSeconds . timesheetTimingBoundaries

decodeRosterShiftTiming :: RosterSlot -> Either RosterShiftIntegrityError ValidatedRosterShiftTiming
decodeRosterShiftTiming slot = do
    startsAt <- maybe (Left (RosterShiftTimingInvalid BoundaryShiftShapeInvalid)) Right slot.startsAt
    endsAt <- maybe (Left (RosterShiftTimingInvalid BoundaryShiftShapeInvalid)) Right slot.endsAt
    boundaries <-
        authoritativeBoundariesFromInstants slot.timezone startsAt endsAt Nothing Nothing
            |> mapLeft RosterShiftTimingInvalid
    pure (ValidatedRosterShiftTiming boundaries)

rosterShiftTimingBoundaries :: ValidatedRosterShiftTiming -> AuthoritativeBoundaries
rosterShiftTimingBoundaries (ValidatedRosterShiftTiming boundaries) = boundaries

rosterShiftTimingStartTime :: ValidatedRosterShiftTiming -> TimeOfDay
rosterShiftTimingStartTime = (.localTimeOfDay) . authoritativeStartLocalTime . rosterShiftTimingBoundaries

rosterShiftTimingEndTime :: ValidatedRosterShiftTiming -> TimeOfDay
rosterShiftTimingEndTime = (.localTimeOfDay) . authoritativeEndLocalTime . rosterShiftTimingBoundaries

rosterShiftTimingElapsedSeconds :: ValidatedRosterShiftTiming -> NominalDiffTime
rosterShiftTimingElapsedSeconds = authoritativeElapsedSeconds . rosterShiftTimingBoundaries

rosterShiftTimingStartOccurrence :: ValidatedRosterShiftTiming -> Maybe RepeatedTimeOccurrence
rosterShiftTimingStartOccurrence = authoritativeStartOccurrence . rosterShiftTimingBoundaries

rosterShiftTimingEndOccurrence :: ValidatedRosterShiftTiming -> Maybe RepeatedTimeOccurrence
rosterShiftTimingEndOccurrence = authoritativeEndOccurrence . rosterShiftTimingBoundaries

timesheetEntryBoundaries :: TimesheetEntry -> Either BoundaryModelError AuthoritativeBoundaries
timesheetEntryBoundaries entry =
    authoritativeBoundariesFromInstants
        entry.timezone
        entry.startsAt
        entry.endsAt
        entry.breakStartsAt
        entry.breakEndsAt

timesheetEntryOperationalDate :: TimesheetEntry -> Day
timesheetEntryOperationalDate = (.operationalDate)

-- Local start date remains an authoritative instant projection for payroll
-- component/calendar conditions. Timesheet planning and presentation use
-- 'timesheetEntryOperationalDate' instead.
timesheetEntryWorkedOn :: TimesheetEntry -> Either TimesheetIntegrityError Day
timesheetEntryWorkedOn = fmap timesheetTimingWorkedOn . decodeTimesheetTiming

timesheetEntryStartTime :: TimesheetEntry -> Either TimesheetIntegrityError TimeOfDay
timesheetEntryStartTime = fmap timesheetTimingStartTime . decodeTimesheetTiming

timesheetEntryEndTime :: TimesheetEntry -> Either TimesheetIntegrityError TimeOfDay
timesheetEntryEndTime = fmap timesheetTimingEndTime . decodeTimesheetTiming

timesheetEntryHadBreak :: TimesheetEntry -> Bool
timesheetEntryHadBreak = isJust . (.breakStartsAt)

timesheetEntryBreakStartTime :: TimesheetEntry -> Either TimesheetIntegrityError (Maybe TimeOfDay)
timesheetEntryBreakStartTime = fmap timesheetTimingBreakStartTime . decodeTimesheetTiming

timesheetEntryBreakEndTime :: TimesheetEntry -> Either TimesheetIntegrityError (Maybe TimeOfDay)
timesheetEntryBreakEndTime = fmap timesheetTimingBreakEndTime . decodeTimesheetTiming

timesheetEntryBreakElapsedSeconds :: TimesheetEntry -> Either TimesheetIntegrityError NominalDiffTime
timesheetEntryBreakElapsedSeconds = fmap timesheetTimingBreakElapsedSeconds . decodeTimesheetTiming

timesheetEntryElapsedSeconds :: TimesheetEntry -> Either TimesheetIntegrityError NominalDiffTime
timesheetEntryElapsedSeconds = fmap timesheetTimingElapsedSeconds . decodeTimesheetTiming

timesheetEntryPaidElapsedSeconds :: TimesheetEntry -> Either TimesheetIntegrityError NominalDiffTime
timesheetEntryPaidElapsedSeconds = fmap timesheetTimingPaidElapsedSeconds . decodeTimesheetTiming

rosterSlotStartTime :: RosterSlot -> Maybe TimeOfDay
rosterSlotStartTime slot = fmap (.localTimeOfDay) (recoverStoredInstantLocalTime slot.timezone slot.startsAt)

rosterSlotEndTime :: RosterSlot -> Maybe TimeOfDay
rosterSlotEndTime slot = fmap (.localTimeOfDay) (recoverStoredInstantLocalTime slot.timezone slot.endsAt)

rosterSlotElapsedSeconds :: RosterSlot -> Maybe NominalDiffTime
rosterSlotElapsedSeconds = fmap rosterShiftTimingElapsedSeconds . eitherToMaybe . decodeRosterShiftTiming

rosterSlotStartOccurrence :: RosterSlot -> Maybe RepeatedTimeOccurrence
rosterSlotStartOccurrence slot = eitherToMaybe (decodeRosterShiftTiming slot) >>= rosterShiftTimingStartOccurrence

rosterSlotEndOccurrence :: RosterSlot -> Maybe RepeatedTimeOccurrence
rosterSlotEndOccurrence slot = eitherToMaybe (decodeRosterShiftTiming slot) >>= rosterShiftTimingEndOccurrence

storedInstantLocalTime :: Text -> UTCTime -> Either BoundaryModelError LocalTime
storedInstantLocalTime timezone instant = do
    validateTimezone timezone
    pure (resolvedInstantLocalTime (resolvedInstantFromUTC instant))

storedInstantOccurrence :: Text -> UTCTime -> Either BoundaryModelError (Maybe RepeatedTimeOccurrence)
storedInstantOccurrence timezone instant = do
    validateTimezone timezone
    pure (resolvedInstantOccurrence (resolvedInstantFromUTC instant))

recoverStoredInstantLocalTime :: Text -> Maybe UTCTime -> Maybe LocalTime
recoverStoredInstantLocalTime timezone maybeInstant =
    either (const Nothing) Just . storedInstantLocalTime timezone =<< maybeInstant

recoverStoredInstantOccurrence :: Text -> Maybe UTCTime -> Maybe RepeatedTimeOccurrence
recoverStoredInstantOccurrence timezone maybeInstant =
    join (either (const Nothing) Just . storedInstantOccurrence timezone =<< maybeInstant)

validatePersistedTimezone :: Text -> Either BoundaryModelError ()
validatePersistedTimezone = validateTimezone

-- Limited to lossy presentation recovery. Strict payroll, copy, publish, and
-- approval paths must retain the full decode error instead.
eitherToMaybe :: Either error value -> Maybe value
eitherToMaybe = either (const Nothing) Just

occurrenceParamValue :: Maybe RepeatedTimeOccurrence -> Text
occurrenceParamValue Nothing                 = ""
occurrenceParamValue (Just FirstOccurrence)  = "first"
occurrenceParamValue (Just SecondOccurrence) = "second"

parseOccurrenceParam :: Text -> Either Text (Maybe RepeatedTimeOccurrence)
parseOccurrenceParam ""       = Right Nothing
parseOccurrenceParam "first"  = Right (Just FirstOccurrence)
parseOccurrenceParam "second" = Right (Just SecondOccurrence)
parseOccurrenceParam _        = Left "Choose the first or second occurrence."

civilBoundaryIsRepeated :: Day -> TimeOfDay -> Bool
civilBoundaryIsRepeated day timeOfDay =
    case resolveCivilTime (civilTime day timeOfDay Nothing) of
        Left RepeatedCivilTimeRequiresOccurrence {} -> True
        _                                           -> False

repeatedEndpointPairCanShareDate :: Day -> TimeOfDay -> TimeOfDay -> Bool
repeatedEndpointPairCanShareDate day startTime endTime =
    endTime <= startTime
        && civilBoundaryIsRepeated day startTime
        && civilBoundaryIsRepeated day endTime

civilTime :: Day -> TimeOfDay -> Maybe RepeatedTimeOccurrence -> MelbourneCivilTime
civilTime civilDate civilTimeOfDay repeatedTimeOccurrence = MelbourneCivilTime { .. }

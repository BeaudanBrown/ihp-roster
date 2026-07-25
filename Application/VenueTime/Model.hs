module Application.VenueTime.Model
    ( BoundaryModelError (..)
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
    , timesheetEntryWorkedOn
    , timesheetEntryStartTime
    , timesheetEntryEndTime
    , timesheetEntryHadBreak
    , timesheetEntryBreakStartTime
    , timesheetEntryBreakEndTime
    , timesheetEntryBreakMinutes
    , timesheetEntryElapsedSeconds
    , timesheetEntryPaidElapsedSeconds
    , rosterSlotStartTime
    , rosterSlotEndTime
    , rosterSlotDurationMinutes
    , rosterSlotStartOccurrence
    , rosterSlotEndOccurrence
    , melbourneDateRangeUTC
    , requireMelbourneDateRangeUTC
    , occurrenceParamValue
    , parseOccurrenceParam
    , civilBoundaryIsRepeated
    , repeatedEndpointPairCanShareDate
    , storedInstantLocalTime
    , storedInstantOccurrence
    ) where

import Application.VenueTime
import Control.Monad (guard)
import Data.Time.Calendar (addDays, diffDays)
import Data.Time.Clock (NominalDiffTime, UTCTime, diffUTCTime)
import Data.Time.LocalTime (LocalTime (..), TimeOfDay, midnight)
import Data.Traversable (traverse)
import Generated.Types
import IHP.HaskellSupport (set)
import IHP.Prelude
import qualified IHP.Prelude as Prelude

mapLeft :: (left -> mappedLeft) -> Either left value -> Either mappedLeft value
mapLeft transform = either (Left . transform) Right

-- | Integration errors stay typed at the form/model boundary. The pure
-- 'Application.VenueTime' errors are retained without string parsing.
data BoundaryModelError
    = BoundaryCivilTimeError !VenueTimeError
    | BoundaryUnsupportedTimezone !Text
    | BoundaryBreakNotContained
    | BoundaryBreakShapeInvalid
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

timesheetEntryBoundaries :: TimesheetEntry -> Either BoundaryModelError AuthoritativeBoundaries
timesheetEntryBoundaries entry =
    authoritativeBoundariesFromInstants
        entry.timezone
        entry.startsAt
        entry.endsAt
        entry.breakStartsAt
        entry.breakEndsAt

timesheetEntryWorkedOn :: TimesheetEntry -> Day
timesheetEntryWorkedOn = (.localDay) . authoritativeStartLocalTime . requireTimesheetBoundaries

timesheetEntryStartTime :: TimesheetEntry -> TimeOfDay
timesheetEntryStartTime = (.localTimeOfDay) . authoritativeStartLocalTime . requireTimesheetBoundaries

timesheetEntryEndTime :: TimesheetEntry -> TimeOfDay
timesheetEntryEndTime = (.localTimeOfDay) . authoritativeEndLocalTime . requireTimesheetBoundaries

timesheetEntryHadBreak :: TimesheetEntry -> Bool
timesheetEntryHadBreak = isJust . (.breakStartsAt)

timesheetEntryBreakStartTime :: TimesheetEntry -> Maybe TimeOfDay
timesheetEntryBreakStartTime = fmap (.localTimeOfDay) . authoritativeBreakStartLocalTime . requireTimesheetBoundaries

timesheetEntryBreakEndTime :: TimesheetEntry -> Maybe TimeOfDay
timesheetEntryBreakEndTime = fmap (.localTimeOfDay) . authoritativeBreakEndLocalTime . requireTimesheetBoundaries

timesheetEntryBreakMinutes :: TimesheetEntry -> Int
timesheetEntryBreakMinutes = floor . (/ 60) . authoritativeBreakElapsedSeconds . requireTimesheetBoundaries

timesheetEntryElapsedSeconds :: TimesheetEntry -> NominalDiffTime
timesheetEntryElapsedSeconds = authoritativeElapsedSeconds . requireTimesheetBoundaries

timesheetEntryPaidElapsedSeconds :: TimesheetEntry -> NominalDiffTime
timesheetEntryPaidElapsedSeconds = authoritativePaidElapsedSeconds . requireTimesheetBoundaries

requireTimesheetBoundaries :: TimesheetEntry -> AuthoritativeBoundaries
requireTimesheetBoundaries entry =
    either (error . ("Invalid persisted timesheet boundaries: " <>) . show) Prelude.id (timesheetEntryBoundaries entry)

rosterSlotStartTime :: RosterSlot -> Maybe TimeOfDay
rosterSlotStartTime slot = ((.localTimeOfDay) . localTimeOfStoredInstant slot.timezone) <$> slot.startsAt

rosterSlotEndTime :: RosterSlot -> Maybe TimeOfDay
rosterSlotEndTime slot = ((.localTimeOfDay) . localTimeOfStoredInstant slot.timezone) <$> slot.endsAt

rosterSlotDurationMinutes :: RosterSlot -> Maybe Int
rosterSlotDurationMinutes slot = do
    start <- slot.startsAt
    end <- slot.endsAt
    guard (end > start)
    pure (floor (diffUTCTime end start / 60))

rosterSlotStartOccurrence :: RosterSlot -> Maybe RepeatedTimeOccurrence
rosterSlotStartOccurrence slot = slot.startsAt >>= occurrenceOfStoredInstant slot.timezone

rosterSlotEndOccurrence :: RosterSlot -> Maybe RepeatedTimeOccurrence
rosterSlotEndOccurrence slot = slot.endsAt >>= occurrenceOfStoredInstant slot.timezone

storedInstantLocalTime :: Text -> UTCTime -> LocalTime
storedInstantLocalTime = localTimeOfStoredInstant

storedInstantOccurrence :: Text -> UTCTime -> Maybe RepeatedTimeOccurrence
storedInstantOccurrence = occurrenceOfStoredInstant

localTimeOfStoredInstant :: Text -> UTCTime -> LocalTime
localTimeOfStoredInstant timezone instant =
    case validateTimezone timezone of
        Left failure -> error ("Invalid persisted timezone snapshot: " <> show failure)
        Right () -> resolvedInstantLocalTime (resolvedInstantFromUTC instant)

occurrenceOfStoredInstant :: Text -> UTCTime -> Maybe RepeatedTimeOccurrence
occurrenceOfStoredInstant timezone instant =
    case validateTimezone timezone of
        Left failure -> error ("Invalid persisted timezone snapshot: " <> show failure)
        Right () -> resolvedInstantOccurrence (resolvedInstantFromUTC instant)

melbourneDateRangeUTC :: Day -> Day -> Either BoundaryModelError (UTCTime, UTCTime)
melbourneDateRangeUTC firstDay lastDay = do
    interval <- resolveShiftBoundaries melbourneTimeZoneName ShiftBoundaryInput
        { shiftBoundaryDate = firstDay
        , shiftBoundaryStartTime = midnight
        , shiftBoundaryStartOccurrence = Nothing
        , shiftBoundaryEndTime = midnight
        , shiftBoundaryEndOccurrence = Nothing
        , shiftBoundaryBreak = Nothing
        }
    let requestedEnd = addDays 1 lastDay
    end <- mapLeft BoundaryCivilTimeError $ resolveCivilTime (civilTime requestedEnd midnight Nothing)
    pure (authoritativeStartsAt interval, resolvedInstantUTC end)

requireMelbourneDateRangeUTC :: Day -> Day -> (UTCTime, UTCTime)
requireMelbourneDateRangeUTC firstDay lastDay =
    either (error . ("Invalid Melbourne date range: " <>) . show) Prelude.id (melbourneDateRangeUTC firstDay lastDay)

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

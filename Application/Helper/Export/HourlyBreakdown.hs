module Application.Helper.Export.HourlyBreakdown
    ( buildHourlyReportWindow
    , buildHourlyShiftTypeColumns
    , buildHourlyWageCents
    , entryHoursForHourlyWindow
    , formatHourlyWindowRange
    , hourlyReportHours
    , roundRationalAt
    ) where

import Application.Helper.Export.Types
import Application.Helper.TimeRules (normalizeWindowEndMinute)
import Application.Helper.TimesheetPayLedger (roundWageLedgerRational)
import Application.VenueTime (RepeatedTimeOccurrence (..))
import Application.VenueTime.Model (TimesheetIntegrityError,
                                    authoritativeEndLocalTime,
                                    authoritativeStartLocalTime,
                                    civilBoundaryIsRepeated,
                                    decodeTimesheetTiming,
                                    resolveBoundaryInstant,
                                    storedInstantLocalTime,
                                    timesheetTimingBoundaries)
import Application.WageEngine
import Control.Monad (foldM, zipWithM)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Ord (Down (..))
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (NominalDiffTime, UTCTime, diffUTCTime)
import Data.Time.LocalTime (LocalTime (..), TimeOfDay (..), addLocalTime)
import Data.Traversable (traverse)
import Generated.Types
import IHP.ControllerPrelude
import Text.Printf (printf)

buildHourlyReportWindow :: VenueConfig -> [TimesheetEntry] -> Either TimesheetIntegrityError HourlyReportWindow
buildHourlyReportWindow venueConfig entries = do
    entriesWithTiming <- traverse (\entry -> (entry,) <$> decodeTimesheetTiming entry) entries
    pure HourlyReportWindow
        { hourlyWindowStartHour = minimum (configuredStartHour : map entryStartHour entriesWithTiming)
        , hourlyWindowEndHour = maximum (configuredEndHour : map entryEndHour entriesWithTiming)
        }
  where
    configuredStartMinute = venueConfig.timePickerStartMinuteOfDay
    configuredEndMinute = normalizeWindowEndMinute configuredStartMinute venueConfig.timePickerFinalSelectableMinuteOfDay
    configuredStartHour = configuredStartMinute `div` 60
    configuredEndHour = ceilingHourForMinute configuredEndMinute

    entryStartHour (entry, timing) =
        localHourFloor entry.operationalDate (authoritativeStartLocalTime (timesheetTimingBoundaries timing))

    entryEndHour (entry, timing) =
        localHourCeiling entry.operationalDate (authoritativeEndLocalTime (timesheetTimingBoundaries timing))

hourlyReportHours :: HourlyReportWindow -> [Int]
hourlyReportHours window = [window.hourlyWindowStartHour .. window.hourlyWindowEndHour - 1]

formatHourlyWindowRange :: Int -> Text
formatHourlyWindowRange hourOfWindow =
    formatHour hourOfWindow <> "-" <> formatHour (hourOfWindow + 1) <> endDaySuffix
  where
    formatHour hour = Text.pack (printf "%02d:00" (hour `mod` 24) :: String)
    endDayOffset = (hourOfWindow + 1) `div` 24
    endDaySuffix = if endDayOffset <= 0 then "" else "+" <> tshow endDayOffset

buildHourlyShiftTypeColumns ::
    [ShiftType] ->
    [ShiftType] ->
    [TimesheetEntry] ->
    Map.Map UUID Text ->
    [HourlyShiftTypeColumn]
buildHourlyShiftTypeColumns activeShiftTypes referencedShiftTypes entries labelsByEntryId =
    disambiguateLabels orderedColumns
  where
    activeIds = Map.fromList [(unpackId shiftType.id, ()) | shiftType <- activeShiftTypes]
    referencedById = Map.fromList [(unpackId shiftType.id, shiftType) | shiftType <- referencedShiftTypes]
    labelsByShiftTypeId =
        foldl'
            (\labels entry ->
                case Map.lookup (unpackId entry.id) labelsByEntryId of
                    Nothing -> labels
                    Just label -> Map.insertWith (flip (<>)) entry.shiftTypeId [label] labels
            )
            Map.empty
            entries

    labelFor shiftType =
        fromMaybe shiftType.name (lastMay (Map.findWithDefault [] (unpackId shiftType.id) labelsByShiftTypeId))

    activeColumns =
        [ HourlyShiftTypeColumn
            { hourlyShiftTypeId = unpackId shiftType.id
            , hourlyShiftTypeLabel = labelFor shiftType
            }
        | shiftType <- activeShiftTypes
        ]

    historicalColumns =
        referencedById
            |> Map.elems
            |> filter (\shiftType -> Map.notMember (unpackId shiftType.id) activeIds)
            |> List.sortOn (\shiftType -> (labelFor shiftType, tshow shiftType.id))
            |> map
                (\shiftType ->
                    HourlyShiftTypeColumn
                        { hourlyShiftTypeId = unpackId shiftType.id
                        , hourlyShiftTypeLabel = labelFor shiftType
                        }
                )

    orderedColumns = activeColumns <> historicalColumns

    disambiguateLabels columns = snd (List.mapAccumL disambiguate Map.empty columns)
      where
        labelCounts = Map.fromListWith (+) [(column.hourlyShiftTypeLabel, 1 :: Int) | column <- columns]
        disambiguate seen column =
            let label = column.hourlyShiftTypeLabel
                occurrence = Map.findWithDefault 0 label seen + 1
                requiresSuffix = Map.findWithDefault 0 label labelCounts > 1 || label == "Time" || label == "Total"
                renderedLabel = if requiresSuffix then label <> " (" <> tshow occurrence <> ")" else label
             in (Map.insert label occurrence seen, column { hourlyShiftTypeLabel = renderedLabel })

data TimedEarningsShare = TimedEarningsShare
    { timedShareHour      :: !Int
    , timedShareBucketKey :: !FinalEarningsBucketKey
    , timedShareAmount    :: !Rational
    , timedShareOrdinal   :: !Int
    }
    deriving (Eq, Show)

data IntervalEarningsShare = IntervalEarningsShare
    { intervalShareStart     :: !UTCTime
    , intervalShareEnd       :: !UTCTime
    , intervalShareBucketKey :: !FinalEarningsBucketKey
    , intervalShareAmount    :: !Rational
    }
    deriving (Eq, Show)

buildHourlyWageCents ::
    [TimesheetEntry] ->
    Map.Map UUID WageCalculation ->
    Either Text (Map.Map (Day, Int, UUID) Integer)
buildHourlyWageCents entries calculationsByEntryId =
    foldM accumulateEntry Map.empty entries
  where
    accumulateEntry totals entry = do
        calculation <- maybe
            (Left ("Approved timesheet entry has no sealed wage calculation: " <> tshow entry.id))
            Right
            (Map.lookup (unpackId entry.id) calculationsByEntryId)
        entryCents <- wageCentsForEntry entry calculation
        pure $
            foldl'
                (\result (hour, cents) -> Map.insertWith (+) (entry.operationalDate, hour, entry.shiftTypeId) cents result)
                totals
                (Map.toList entryCents)

wageCentsForEntry :: TimesheetEntry -> WageCalculation -> Either Text (Map.Map Int Integer)
wageCentsForEntry entry calculation = do
    intervalShares <- intervalSharesForCalculation entry.timezone entry.startsAt entry.endsAt calculation
    let timedShares = concatMap (splitIntervalShareIntoHours entry) intervalShares
    allocateFinalEarningsCents calculation timedShares

intervalSharesForCalculation :: Text -> UTCTime -> UTCTime -> WageCalculation -> Either Text [IntervalEarningsShare]
intervalSharesForCalculation timezone entryStartsAt entryEndsAt calculation = do
    let paidSegments = calculation.paidTimeSegments
        (paidComponents, extraComponents) = List.splitAt (length paidSegments) calculation.earningsComponents
        workedSegments = filter ((== Worked) . (.paidTimeKind)) paidSegments
        workedSeconds = sum (map paidTimeDurationSeconds workedSegments)
    when (length paidComponents /= length paidSegments) $
        Left "Approved wage calculation does not contain one base earnings component per paid-time segment."
    paidShares <- concat <$> zipWithM (sharesForPaidComponent workedSegments workedSeconds) paidSegments paidComponents
    extraShares <- sharesForExtraComponents timezone entryStartsAt entryEndsAt workedSegments extraComponents
    pure (paidShares <> extraShares)

sharesForPaidComponent :: [PaidTimeSegment] -> Rational -> PaidTimeSegment -> EarningsComponent -> Either Text [IntervalEarningsShare]
sharesForPaidComponent workedSegments workedSeconds segment component = do
    validatePaidComponent segment component
    case segment.paidTimeKind of
        Worked -> pure [shareForInterval component segment.paidTimeStart segment.paidTimeEnd component.amount]
        _
            | workedSeconds <= 0 -> Left "Approved wage calculation has a minimum-payment top-up but no actual worked time."
            | otherwise ->
                pure
                    [ shareForInterval
                        component
                        worked.paidTimeStart
                        worked.paidTimeEnd
                        (component.amount * paidTimeDurationSeconds worked / workedSeconds)
                    | worked <- workedSegments
                    ]

validatePaidComponent :: PaidTimeSegment -> EarningsComponent -> Either Text ()
validatePaidComponent segment component
    | component.unitType /= Hours = Left "Approved wage calculation base component is not hourly."
    | component.quantity /= roundWageLedgerRational (paidTimeDurationSeconds segment / 3600) = Left "Approved wage calculation base component quantity does not match its paid-time segment."
    | component.sourceCondition /= segment.paidTimeSourceCondition = Left "Approved wage calculation base component condition does not match its paid-time segment."
    | otherwise = Right ()

sharesForExtraComponents :: Text -> UTCTime -> UTCTime -> [PaidTimeSegment] -> [EarningsComponent] -> Either Text [IntervalEarningsShare]
sharesForExtraComponents timezone entryStartsAt entryEndsAt workedSegments components = snd <$> foldM allocate (Map.empty, []) components
  where
    allocate (conditionCounts, shares) component =
        case (component.unitType, component.sourceCondition) of
            (CommencedHours, condition@EveningAdditionCondition) -> allocateCommenced conditionCounts shares condition component
            (CommencedHours, condition@EarlyMorningAdditionCondition) -> allocateCommenced conditionCounts shares condition component
            (Hours, MissedMealBreakAdditionCondition) -> do
                missedShare <- shareForMissedBreak entryStartsAt entryEndsAt component
                pure (conditionCounts, shares <> [missedShare])
            _ -> Left "Approved wage calculation contains an unsupported extra earnings component for hourly attribution."

    allocateCommenced conditionCounts shares condition component = do
        let eligible = filter (qualifiesForCommenced timezone condition) workedSegments
            dates = List.sort (List.nub (map (.paidTimeLocalDate) eligible))
            occurrence = Map.findWithDefault 0 condition conditionCounts
        date <- maybe
            (Left "Approved commenced-hour addition has no matching qualifying worked interval.")
            Right
            (safeListIndex dates occurrence)
        let datedEligible = filter ((== date) . (.paidTimeLocalDate)) eligible
            totalSeconds = sum (map paidTimeDurationSeconds datedEligible)
        when (totalSeconds <= 0) $
            Left "Approved commenced-hour addition has no positive qualifying worked duration."
        let componentShares =
                [ shareForInterval
                    component
                    segment.paidTimeStart
                    segment.paidTimeEnd
                    (component.amount * paidTimeDurationSeconds segment / totalSeconds)
                | segment <- datedEligible
                ]
        pure (Map.insert condition (occurrence + 1) conditionCounts, shares <> componentShares)

shareForMissedBreak :: UTCTime -> UTCTime -> EarningsComponent -> Either Text IntervalEarningsShare
shareForMissedBreak entryStartsAt entryEndsAt component = do
    let missedStart = addUTCTime (6 * 60 * 60) entryStartsAt
        missedEnd = addUTCTime (fromRational (component.quantity * 3600)) missedStart
    when (component.quantity <= 0 || missedEnd > entryEndsAt) $
        Left "Approved missed-meal-break quantity falls outside its timesheet interval."
    pure (shareForInterval component missedStart missedEnd component.amount)

qualifiesForCommenced :: Text -> SourceCondition -> PaidTimeSegment -> Bool
qualifiesForCommenced timezone condition segment
    | segment.paidTimeSourceCondition == PublicHolidayCondition = False
    | dayOfWeek segment.paidTimeLocalDate `elem` [Saturday, Sunday] = False
    | otherwise =
        case storedInstantLocalTime timezone segment.paidTimeStart of
            Left _ -> False
            Right localTime -> case condition of
                EveningAdditionCondition      -> localTime.localTimeOfDay.todHour >= 19
                EarlyMorningAdditionCondition -> localTime.localTimeOfDay.todHour < 7
                _                             -> False

shareForInterval :: EarningsComponent -> UTCTime -> UTCTime -> Rational -> IntervalEarningsShare
shareForInterval component start end amount =
    IntervalEarningsShare
        { intervalShareStart = start
        , intervalShareEnd = end
        , intervalShareBucketKey = finalEarningsBucketKey component
        , intervalShareAmount = amount
        }

splitIntervalShareIntoHours :: TimesheetEntry -> IntervalEarningsShare -> [TimedEarningsShare]
splitIntervalShareIntoHours entry share =
    [ TimedEarningsShare
        { timedShareHour = fromInteger (diffDays localDate ownershipDate) * 24 + localHour
        , timedShareBucketKey = share.intervalShareBucketKey
        , timedShareAmount = share.intervalShareAmount * toRational elapsed / totalSeconds
        , timedShareOrdinal = ordinal
        }
    | (ordinal, (localDate, localHour, elapsed)) <- zip [0 ..] localSegments
    , elapsed > 0
    ]
  where
    ownershipDate = entry.operationalDate
    localSegments = storedIntervalLocalHourSegments entry.timezone share.intervalShareStart share.intervalShareEnd
    totalSeconds = toRational (diffUTCTime share.intervalShareEnd share.intervalShareStart)

allocateFinalEarningsCents :: WageCalculation -> [TimedEarningsShare] -> Either Text (Map.Map Int Integer)
allocateFinalEarningsCents calculation shares = do
    allocated <- traverse allocateLine publishedLines
    let knownKeys = Map.fromList [(line.finalEarningsLineBucketKey, ()) | line <- publishedLines]
        unknownShares = filter (\share -> Map.notMember share.timedShareBucketKey knownKeys) shares
    unless (null unknownShares) $
        Left "Approved wage calculation contains timed earnings that were not published."
    pure (Map.fromListWith (+) (concat allocated))
  where
    publishedLines = (deriveFinalEarnings calculation.earningsComponents).finalEarningsLines
    sharesByKey = Map.fromListWith (<>) [(share.timedShareBucketKey, [share]) | share <- shares, share.timedShareAmount > 0]

    allocateLine line = do
        let lineShares = Map.findWithDefault [] line.finalEarningsLineBucketKey sharesByKey
            targetCents = round (line.finalEarningsLineRoundedAmount * 100)
        when (targetCents > 0 && null lineShares) $
            Left "Approved wage earnings line has no hourly attribution."
        pure (allocateCents targetCents lineShares)

allocateCents :: Integer -> [TimedEarningsShare] -> [(Int, Integer)]
allocateCents targetCents shares
    | targetCents <= 0 || null shares = []
    | otherwise =
        [ (share.timedShareHour, base + if index `elem` remainderIndexes then 1 else 0)
        | (index, share, base, _) <- quotas
        ]
  where
    totalAmount = sum (map (.timedShareAmount) shares)
    quotas =
        [ let exactQuota = share.timedShareAmount * fromInteger targetCents / totalAmount
           in (index, share, floor exactQuota, exactQuota - fromInteger (floor exactQuota :: Integer))
        | (index, share) <- zip [0 ..] shares
        ]
    allocatedBase = sum [base | (_, _, base, _) <- quotas]
    remainderCount = fromInteger (targetCents - allocatedBase)
    remainderIndexes =
        quotas
            |> List.sortOn (\(index, share, _, remainder) -> (Down remainder, share.timedShareHour, share.timedShareOrdinal, index))
            |> take remainderCount
            |> map (\(index, _, _, _) -> index)

safeListIndex :: [a] -> Int -> Maybe a
safeListIndex values index
    | index < 0 = Nothing
    | otherwise = listToMaybe (drop index values)

entryHoursForHourlyWindow :: Int -> UUID -> TimesheetEntry -> Rational
entryHoursForHourlyWindow hourOfWindow shiftTypeId entry
    | entry.shiftTypeId /= shiftTypeId = 0
    | otherwise =
        let targetDate = addDays (toInteger (hourOfWindow `div` 24)) entry.operationalDate
            targetHour = hourOfWindow `mod` 24
            shiftSeconds = intervalSecondsInLocalHour entry.timezone targetDate targetHour entry.startsAt entry.endsAt
            breakSeconds = case (entry.breakStartsAt, entry.breakEndsAt) of
                (Just breakStartsAt, Just breakEndsAt) -> intervalSecondsInLocalHour entry.timezone targetDate targetHour breakStartsAt breakEndsAt
                _ -> 0
         in toRational (max 0 (shiftSeconds - breakSeconds)) / 3600

intervalSecondsInLocalHour :: Text -> Day -> Int -> UTCTime -> UTCTime -> NominalDiffTime
intervalSecondsInLocalHour timezone targetDate targetHour startsAt endsAt =
    sum
        [ elapsed
        | (localDate, localHour, elapsed) <- storedIntervalLocalHourSegments timezone startsAt endsAt
        , localDate == targetDate
        , localHour == targetHour
        ]

storedIntervalLocalHourSegments :: Text -> UTCTime -> UTCTime -> [(Day, Int, NominalDiffTime)]
storedIntervalLocalHourSegments timezone startsAt endsAt = go startsAt
  where
    go cursor
        | cursor >= endsAt = []
        | otherwise =
            case storedInstantLocalTime timezone cursor of
                Left _ -> []
                Right local ->
                    let segmentEnd = min endsAt (nextStoredLocalHourBoundary timezone cursor local)
                     in (local.localDay, local.localTimeOfDay.todHour, diffUTCTime segmentEnd cursor) : go segmentEnd

nextStoredLocalHourBoundary :: Text -> UTCTime -> LocalTime -> UTCTime
nextStoredLocalHourBoundary timezone cursor local = findBoundary firstCandidateLocal
  where
    localHourStart = LocalTime local.localDay (TimeOfDay local.localTimeOfDay.todHour 0 0)
    firstCandidateLocal = addLocalTime 3600 localHourStart

    findBoundary candidateLocal =
        case filter (> cursor) (resolvedCandidates candidateLocal) of
            []         -> findBoundary (addLocalTime 3600 candidateLocal)
            candidates -> minimum candidates

    resolvedCandidates candidateLocal =
        let occurrences =
                if civilBoundaryIsRepeated candidateLocal.localDay candidateLocal.localTimeOfDay
                    then [Just FirstOccurrence, Just SecondOccurrence]
                    else [Nothing]
         in mapMaybe
                (either (const Nothing) Just . resolveBoundaryInstant timezone candidateLocal.localDay candidateLocal.localTimeOfDay)
                occurrences

roundRationalAt :: Integer -> Rational -> Rational
roundRationalAt scale value = fromInteger (round (value * fromInteger scale)) / fromInteger scale

localHourFloor :: Day -> LocalTime -> Int
localHourFloor ownershipDate local =
    fromInteger (diffDays local.localDay ownershipDate) * 24 + local.localTimeOfDay.todHour

localHourCeiling :: Day -> LocalTime -> Int
localHourCeiling ownershipDate local =
    localHourFloor ownershipDate local
        + if local.localTimeOfDay.todMin == 0 && local.localTimeOfDay.todSec == 0 then 0 else 1

ceilingHourForMinute :: Int -> Int
ceilingHourForMinute minute = (minute + 59) `div` 60

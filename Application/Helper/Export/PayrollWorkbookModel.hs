module Application.Helper.Export.PayrollWorkbookModel
    ( PayrollWorkbookDay (..)
    , PayrollWorkbookFact (..)
    , PayrollWorkbookFactModel (..)
    , PayrollWorkbookHourSlot (..)
    , PayrollWorkbookHourlyModel (..)
    , PayrollWorkbookPayBucket (..)
    , PayrollWorkbookPayBucketKey (..)
    , PayrollWorkbookRow (..)
    , buildPayrollWorkbookFactModel
    , buildPayrollWorkbookHourlyModel
    , payrollWorkbookHourlyModelFromFacts
    ) where

import Application.Helper.Export.HourlyBreakdown
import Application.Helper.Export.Types
import Application.VenueTime.Model (civilBoundaryIsRepeated)
import Application.WageEngine
import Control.Monad (foldM, when)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Ord (Down (..))
import qualified Data.Set as Set
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude

-- | Approval-pinned pay authority. IDs, rather than display labels, control
-- aggregation so two distinct pay selections with the same name never merge.
data PayrollWorkbookPayBucketKey
    = PayrollWorkbookAwardLevel !UUID
    | PayrollWorkbookImportedPayItem !UUID
    deriving (Eq, Ord, Show)

data PayrollWorkbookPayBucket = PayrollWorkbookPayBucket
    { payrollPayBucketKey   :: !PayrollWorkbookPayBucketKey
    , payrollPayBucketLabel :: !Text
    }
    deriving (Eq, Ord, Show)

data PayrollWorkbookHourSlot = PayrollWorkbookHourSlot
    { payrollHourOfWindow   :: !Int
    , payrollHourOccurrence :: !HourlyOccurrence
    }
    deriving (Eq, Ord, Show)

-- | One immutable workbook fact per approved entry and report-window hour
-- occurrence. Presentations aggregate these facts; they never recalculate pay.
data PayrollWorkbookFact = PayrollWorkbookFact
    { payrollFactOperationalDate       :: !Day
    , payrollFactEntryId               :: !UUID
    , payrollFactStaffId               :: !UUID
    , payrollFactStaffFirstName        :: !Text
    , payrollFactStaffLastName         :: !Text
    , payrollFactShiftTypeId           :: !UUID
    , payrollFactShiftTypeLabel        :: !Text
    , payrollFactPayBucket             :: !PayrollWorkbookPayBucket
    , payrollFactHourSlot              :: !PayrollWorkbookHourSlot
    , payrollFactWorkedHours           :: !Rational
    , payrollFactPaidHours             :: !Rational
    , payrollFactWageCents             :: !Integer
    , payrollFactActiveCalculationId   :: !(Maybe UUID)
    , payrollFactStaffPayVersionId     :: !(Maybe UUID)
    , payrollFactShiftTypePayVersionId :: !(Maybe UUID)
    , payrollFactCalculationVersion    :: !Text
    , payrollFactRateBookVersion       :: !(Maybe Text)
    }
    deriving (Eq, Show)

data PayrollWorkbookFactModel = PayrollWorkbookFactModel
    { payrollFactModelRangeStart :: !Day
    , payrollFactModelRangeEnd   :: !Day
    , payrollFactModelWindow     :: !HourlyReportWindow
    , payrollFactModelHourSlots  :: ![PayrollWorkbookHourSlot]
    , payrollFactModelFacts      :: ![PayrollWorkbookFact]
    }
    deriving (Eq, Show)

data PayrollWorkbookRow = PayrollWorkbookRow
    { payrollRowStaffId        :: !UUID
    , payrollRowStaffFirstName :: !Text
    , payrollRowStaffLastName  :: !Text
    , payrollRowPayBucket      :: !PayrollWorkbookPayBucket
    , payrollRowHours          :: ![Rational]
    , payrollRowWageCents      :: ![Integer]
    , payrollRowEntryCount     :: !Int
    }
    deriving (Eq, Show)

data PayrollWorkbookDay = PayrollWorkbookDay
    { payrollDayDate :: !Day
    , payrollDayRows :: ![PayrollWorkbookRow]
    }
    deriving (Eq, Show)

data PayrollWorkbookHourlyModel = PayrollWorkbookHourlyModel
    { payrollModelRangeStart :: !Day
    , payrollModelRangeEnd   :: !Day
    , payrollModelWindow     :: !HourlyReportWindow
    , payrollModelHourSlots  :: ![PayrollWorkbookHourSlot]
    , payrollModelDays       :: ![PayrollWorkbookDay]
    }
    deriving (Eq, Show)

data AccumulatedRow = AccumulatedRow
    { accumulatedStaffFirstName :: !Text
    , accumulatedStaffLastName  :: !Text
    , accumulatedPayBucket      :: !PayrollWorkbookPayBucket
    , accumulatedHours          :: !(Map.Map PayrollWorkbookHourSlot Rational)
    , accumulatedWageCents      :: !(Map.Map PayrollWorkbookHourSlot Integer)
    , accumulatedEntryIds       :: !(Set.Set UUID)
    }

buildPayrollWorkbookHourlyModel ::
    Day ->
    Day ->
    VenueConfig ->
    [TimesheetEntry] ->
    Map.Map UUID Staff ->
    Map.Map UUID PayrollWorkbookPayBucket ->
    Map.Map UUID WageCalculation ->
    Either Text PayrollWorkbookHourlyModel
buildPayrollWorkbookHourlyModel rangeStart rangeEnd venueConfig entries staffById payBucketsByEntryId calculationsByEntryId =
    payrollWorkbookHourlyModelFromFacts
        <$> buildPayrollWorkbookFactModel
            rangeStart
            rangeEnd
            venueConfig
            entries
            staffById
            payBucketsByEntryId
            fallbackShiftLabels
            calculationsByEntryId
  where
    fallbackShiftLabels =
        Map.fromList
            [ (unpackId entry.id, tshow entry.shiftTypeId)
            | entry <- entries
            ]

buildPayrollWorkbookFactModel ::
    Day ->
    Day ->
    VenueConfig ->
    [TimesheetEntry] ->
    Map.Map UUID Staff ->
    Map.Map UUID PayrollWorkbookPayBucket ->
    Map.Map UUID Text ->
    Map.Map UUID WageCalculation ->
    Either Text PayrollWorkbookFactModel
buildPayrollWorkbookFactModel rangeStart rangeEnd venueConfig entries staffById payBucketsByEntryId shiftLabelsByEntryId calculationsByEntryId = do
    when (rangeStart > rangeEnd) $
        Left "Choose a valid start and end date for the Payroll Workbook range."
    when (null entries) $
        Left "No approved payroll entries were found for the Payroll Workbook range."
    facts <- concat <$> mapM factsForEntry (List.sortOn entryOrder entries)
    pure
        PayrollWorkbookFactModel
            { payrollFactModelRangeStart = rangeStart
            , payrollFactModelRangeEnd = rangeEnd
            , payrollFactModelWindow = window
            , payrollFactModelHourSlots = hourSlots
            , payrollFactModelFacts = facts
            }
  where
    dates = [rangeStart .. rangeEnd]
    window = buildHourlyReportWindow venueConfig entries
    hourSlots = concatMap slotsForHour (hourlyReportHours window)

    slotsForHour hour =
        PayrollWorkbookHourSlot hour FirstHourlyOccurrence
            : [ PayrollWorkbookHourSlot hour SecondHourlyOccurrence
              | any (hourRepeatsOnDate venueConfig.timezone hour) dates
              ]

    entryOrder entry = (entry.operationalDate, entry.staffId, entry.startsAt, unpackId entry.id)

    factsForEntry entry = do
        when (entry.operationalDate < rangeStart || entry.operationalDate > rangeEnd) $
            Left ("Payroll Workbook entry falls outside its requested Operational-date range: " <> tshow entry.id)
        staff <- maybe
            (Left ("Payroll Workbook entry has no linked active staff: " <> tshow entry.id))
            Right
            (Map.lookup entry.staffId staffById)
        payBucket <- requireForEntry "approval-pinned pay bucket" entry payBucketsByEntryId
        shiftLabel <- requireForEntry "approval-pinned shift-type label" entry shiftLabelsByEntryId
        calculation <- requireForEntry "sealed wage calculation" entry calculationsByEntryId
        validateCalculationTiming entry calculation
        entryWorkedHours <- workedHoursForEntry entry calculation
        entryPaidHours <- hoursForEntry entry calculation
        entryWageCents <- wageCentsForEntryBySlot entry calculation
        let publishedWageCents =
                deriveFinalEarnings calculation.earningsComponents
                    |> (.finalEarningsLines)
                    |> map (\line -> round (line.finalEarningsLineRoundedAmount * 100))
                    |> sum
        when (sum (Map.elems entryWageCents) /= publishedWageCents) $
            Left ("Payroll Workbook hourly wages do not reconcile to sealed earnings: " <> tshow entry.id)
        let keyedWorkedHours = keyedBySlot entryWorkedHours
        let keyedPaidHours = keyedBySlot entryPaidHours
        let keyedWages = keyedBySlot entryWageCents
        let allowedSlots = Set.fromList hourSlots
        let publishedSlots =
                Set.unions
                    [ Map.keysSet keyedWorkedHours
                    , Map.keysSet keyedPaidHours
                    , Map.keysSet keyedWages
                    ]
        unless (Set.isSubsetOf publishedSlots allowedSlots) $
            Left ("Payroll Workbook hourly facts fall outside the shared report window: " <> tshow entry.id)
        pure
            [ PayrollWorkbookFact
                { payrollFactOperationalDate = entry.operationalDate
                , payrollFactEntryId = unpackId entry.id
                , payrollFactStaffId = entry.staffId
                , payrollFactStaffFirstName = staff.firstName
                , payrollFactStaffLastName = staff.lastName
                , payrollFactShiftTypeId = entry.shiftTypeId
                , payrollFactShiftTypeLabel = shiftLabel
                , payrollFactPayBucket = payBucket
                , payrollFactHourSlot = slot
                , payrollFactWorkedHours = Map.findWithDefault 0 slot keyedWorkedHours
                , payrollFactPaidHours = Map.findWithDefault 0 slot keyedPaidHours
                , payrollFactWageCents = Map.findWithDefault 0 slot keyedWages
                , payrollFactActiveCalculationId = fmap unpackId entry.activePayCalculationId
                , payrollFactStaffPayVersionId = entry.staffPayVersionId
                , payrollFactShiftTypePayVersionId = entry.shiftTypePayVersionId
                , payrollFactCalculationVersion = calculationVersionText calculation.calculationVersion
                , payrollFactRateBookVersion = rateBookVersionText <$> calculation.calculationRateBookVersion
                }
            | slot <- hourSlots
            ]

    keyedBySlot values =
        Map.fromListWith (+)
            [ (PayrollWorkbookHourSlot hour occurrence, value)
            | ((hour, occurrence), value) <- Map.toList values
            ]

payrollWorkbookHourlyModelFromFacts :: PayrollWorkbookFactModel -> PayrollWorkbookHourlyModel
payrollWorkbookHourlyModelFromFacts factModel =
    PayrollWorkbookHourlyModel
        { payrollModelRangeStart = factModel.payrollFactModelRangeStart
        , payrollModelRangeEnd = factModel.payrollFactModelRangeEnd
        , payrollModelWindow = factModel.payrollFactModelWindow
        , payrollModelHourSlots = factModel.payrollFactModelHourSlots
        , payrollModelDays = map buildDay [factModel.payrollFactModelRangeStart .. factModel.payrollFactModelRangeEnd]
        }
  where
    accumulatedRows = foldl' accumulateFact Map.empty factModel.payrollFactModelFacts

    accumulateFact rows fact =
        Map.insertWith combineRows rowKey newRow rows
      where
        rowKey = (fact.payrollFactOperationalDate, fact.payrollFactStaffId, fact.payrollFactPayBucket.payrollPayBucketKey)
        newRow =
            AccumulatedRow
                { accumulatedStaffFirstName = fact.payrollFactStaffFirstName
                , accumulatedStaffLastName = fact.payrollFactStaffLastName
                , accumulatedPayBucket = fact.payrollFactPayBucket
                , accumulatedHours = Map.singleton fact.payrollFactHourSlot fact.payrollFactPaidHours
                , accumulatedWageCents = Map.singleton fact.payrollFactHourSlot fact.payrollFactWageCents
                , accumulatedEntryIds = Set.singleton fact.payrollFactEntryId
                }

    buildDay date =
        PayrollWorkbookDay
            { payrollDayDate = date
            , payrollDayRows =
                accumulatedRows
                    |> Map.toList
                    |> mapMaybe (rowForDate date)
                    |> List.sortOn rowOrder
            }

    rowForDate date ((rowDate, staffId, _payBucketKey), accumulated)
        | rowDate /= date = Nothing
        | otherwise =
            let exactHours = map (\slot -> Map.findWithDefault 0 slot accumulated.accumulatedHours) factModel.payrollFactModelHourSlots
             in Just
                    PayrollWorkbookRow
                        { payrollRowStaffId = staffId
                        , payrollRowStaffFirstName = accumulated.accumulatedStaffFirstName
                        , payrollRowStaffLastName = accumulated.accumulatedStaffLastName
                        , payrollRowPayBucket = accumulated.accumulatedPayBucket
                        , payrollRowHours = roundHoursWithResidual exactHours
                        , payrollRowWageCents = map (\slot -> Map.findWithDefault 0 slot accumulated.accumulatedWageCents) factModel.payrollFactModelHourSlots
                        , payrollRowEntryCount = Set.size accumulated.accumulatedEntryIds
                        }

    rowOrder row =
        ( row.payrollRowStaffLastName
        , row.payrollRowStaffFirstName
        , row.payrollRowStaffId
        , row.payrollRowPayBucket.payrollPayBucketLabel
        , row.payrollRowPayBucket.payrollPayBucketKey
        )

calculationVersionText :: WageCalculationVersion -> Text
calculationVersionText (WageCalculationVersion value) = value

rateBookVersionText :: RateBookVersion -> Text
rateBookVersionText (RateBookVersion value) = value

requireForEntry :: Text -> TimesheetEntry -> Map.Map UUID value -> Either Text value
requireForEntry authority entry values =
    maybe
        (Left ("Payroll Workbook entry has no " <> authority <> ": " <> tshow entry.id))
        Right
        (Map.lookup (unpackId entry.id) values)

validateCalculationTiming :: TimesheetEntry -> WageCalculation -> Either Text ()
validateCalculationTiming entry calculation = do
    when (calculation.calculatedEntryId /= CalculationEntryId (tshow (unpackId entry.id))) $
        Left ("Payroll Workbook sealed wage calculation belongs to another entry: " <> tshow entry.id)
    when (calculation.publishedOperationalDate /= Just entry.operationalDate) $
        Left ("Payroll Workbook sealed wage calculation has a missing or mismatched Operational date: " <> tshow entry.id)
    forM_ calculation.paidTimeSegments \segment -> do
        when (segment.paidTimeStart >= segment.paidTimeEnd) $
            Left ("Payroll Workbook sealed paid-time segment is not positive: " <> tshow entry.id)
        when
            ( segment.paidTimeKind == Worked
                && (segment.paidTimeStart < entry.startsAt || segment.paidTimeEnd > entry.endsAt)
            ) $
            Left ("Payroll Workbook worked segment falls outside its timesheet interval: " <> tshow entry.id)

combineRows :: AccumulatedRow -> AccumulatedRow -> AccumulatedRow
combineRows new existing =
    existing
        { accumulatedHours = Map.unionWith (+) existing.accumulatedHours new.accumulatedHours
        , accumulatedWageCents = Map.unionWith (+) existing.accumulatedWageCents new.accumulatedWageCents
        , accumulatedEntryIds = Set.union existing.accumulatedEntryIds new.accumulatedEntryIds
        }

workedHoursForEntry :: TimesheetEntry -> WageCalculation -> Either Text (Map.Map (Int, HourlyOccurrence) Rational)
workedHoursForEntry entry calculation = do
    let workedSegments = filter ((== Worked) . (.paidTimeKind)) calculation.paidTimeSegments
    when (null workedSegments) $
        Left ("Payroll Workbook entry has no positive actual worked time: " <> tshow entry.id)
    pure
        ( Map.fromListWith (+) (concatMap (segmentSecondsBySlot entry) workedSegments)
            |> Map.map (/ 3600)
        )

hoursForEntry :: TimesheetEntry -> WageCalculation -> Either Text (Map.Map (Int, HourlyOccurrence) Rational)
hoursForEntry entry calculation = do
    let workedSegments = filter ((== Worked) . (.paidTimeKind)) calculation.paidTimeSegments
    let workedSeconds = sum (map paidTimeDurationSeconds workedSegments)
    let paidSeconds = sum (map paidTimeDurationSeconds calculation.paidTimeSegments)
    when (workedSeconds <= 0) $
        Left ("Payroll Workbook entry has no positive actual worked time: " <> tshow entry.id)
    when (paidSeconds < workedSeconds) $
        Left ("Payroll Workbook entry has invalid paid-time totals: " <> tshow entry.id)
    let workedBySlot = Map.fromListWith (+) (concatMap (segmentSecondsBySlot entry) workedSegments)
    pure (Map.map (\seconds -> seconds * paidSeconds / workedSeconds / 3600) workedBySlot)

segmentSecondsBySlot :: TimesheetEntry -> PaidTimeSegment -> [((Int, HourlyOccurrence), Rational)]
segmentSecondsBySlot entry segment =
    [ ( (fromInteger (diffDays date entry.operationalDate) * 24 + hour, occurrence)
      , toRational elapsed
      )
    | (date, hour, occurrence, elapsed) <-
        storedIntervalLocalHourOccurrenceSegments entry.timezone segment.paidTimeStart segment.paidTimeEnd
    , elapsed > 0
    ]

roundHoursWithResidual :: [Rational] -> [Rational]
roundHoursWithResidual values =
    [ fromInteger (base + if index `elem` remainderIndexes then 1 else 0) / hourScale
    | (index, base, _remainder) <- quotas
    ]
  where
    hourScale = 1000000
    targetUnits = round (sum values * hourScale)
    quotas =
        [ let exactUnits = value * hourScale
           in (index, floor exactUnits, exactUnits - fromInteger (floor exactUnits :: Integer))
        | (index, value) <- zip [0 :: Int ..] values
        ]
    baseUnits = sum [base | (_index, base, _remainder) <- quotas]
    remainderCount = fromInteger (targetUnits - baseUnits)
    remainderIndexes =
        quotas
            |> List.sortOn (\(index, _base, remainder) -> (Down remainder, index))
            |> take remainderCount
            |> map (\(index, _base, _remainder) -> index)

hourRepeatsOnDate :: Text -> Int -> Day -> Bool
hourRepeatsOnDate timezone hourOfWindow operationalDate =
    timezone == "Australia/Melbourne"
        && civilBoundaryIsRepeated localDate (TimeOfDay localHour 0 0)
  where
    localDate = addDays (toInteger (hourOfWindow `div` 24)) operationalDate
    localHour = hourOfWindow `mod` 24

module Application.Helper.Export.PayrollWorkbookModel
    ( PayrollWorkbookDay (..)
    , PayrollWorkbookHourSlot (..)
    , PayrollWorkbookHourlyModel (..)
    , PayrollWorkbookPayBucket (..)
    , PayrollWorkbookPayBucketKey (..)
    , PayrollWorkbookRow (..)
    , buildPayrollWorkbookHourlyModel
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
    { accumulatedStaff      :: !Staff
    , accumulatedPayBucket  :: !PayrollWorkbookPayBucket
    , accumulatedHours      :: !(Map.Map PayrollWorkbookHourSlot Rational)
    , accumulatedWageCents  :: !(Map.Map PayrollWorkbookHourSlot Integer)
    , accumulatedEntryCount :: !Int
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
buildPayrollWorkbookHourlyModel rangeStart rangeEnd venueConfig entries staffById payBucketsByEntryId calculationsByEntryId = do
    when (rangeStart > rangeEnd) $
        Left "Choose a valid start and end date for the Payroll Workbook range."
    when (null entries) $
        Left "No approved payroll entries were found for the Payroll Workbook range."
    accumulatedRows <- foldM accumulateEntry Map.empty (List.sortOn entryOrder entries)
    pure
        PayrollWorkbookHourlyModel
            { payrollModelRangeStart = rangeStart
            , payrollModelRangeEnd = rangeEnd
            , payrollModelWindow = window
            , payrollModelHourSlots = hourSlots
            , payrollModelDays = map (buildDay accumulatedRows) dates
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

    accumulateEntry rows entry = do
        when (entry.operationalDate < rangeStart || entry.operationalDate > rangeEnd) $
            Left ("Payroll Workbook entry falls outside its requested Operational-date range: " <> tshow entry.id)
        staff <- maybe
            (Left ("Payroll Workbook entry has no linked active staff: " <> tshow entry.id))
            Right
            (Map.lookup entry.staffId staffById)
        payBucket <- requireForEntry "approval-pinned pay bucket" entry payBucketsByEntryId
        calculation <- requireForEntry "sealed wage calculation" entry calculationsByEntryId
        validateCalculationTiming entry calculation
        entryHours <- hoursForEntry entry calculation
        entryWageCents <- wageCentsForEntryBySlot entry calculation
        let publishedWageCents =
                deriveFinalEarnings calculation.earningsComponents
                    |> (.finalEarningsLines)
                    |> map (\line -> round (line.finalEarningsLineRoundedAmount * 100))
                    |> sum
        when (sum (Map.elems entryWageCents) /= publishedWageCents) $
            Left ("Payroll Workbook hourly wages do not reconcile to sealed earnings: " <> tshow entry.id)
        let keyedHours = Map.fromListWith (+)
                [ (PayrollWorkbookHourSlot hour occurrence, value)
                | ((hour, occurrence), value) <- Map.toList entryHours
                ]
        let keyedWages = Map.fromListWith (+)
                [ (PayrollWorkbookHourSlot hour occurrence, value)
                | ((hour, occurrence), value) <- Map.toList entryWageCents
                ]
        let allowedSlots = Set.fromList hourSlots
        let outsideWindowSlots =
                Set.difference
                    (Set.union (Map.keysSet keyedHours) (Map.keysSet keyedWages))
                    allowedSlots
        unless (Set.null outsideWindowSlots) $
            Left ("Payroll Workbook hourly facts fall outside the shared report window: " <> tshow entry.id)
        let rowKey = (entry.operationalDate, entry.staffId, payBucket.payrollPayBucketKey)
        let newRow =
                AccumulatedRow
                    { accumulatedStaff = staff
                    , accumulatedPayBucket = payBucket
                    , accumulatedHours = keyedHours
                    , accumulatedWageCents = keyedWages
                    , accumulatedEntryCount = 1
                    }
        pure (Map.insertWith combineRows rowKey newRow rows)

    buildDay accumulatedRows date =
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
            let exactHours = map (\slot -> Map.findWithDefault 0 slot accumulated.accumulatedHours) hourSlots
             in Just
                    PayrollWorkbookRow
                        { payrollRowStaffId = staffId
                        , payrollRowStaffFirstName = accumulated.accumulatedStaff.firstName
                        , payrollRowStaffLastName = accumulated.accumulatedStaff.lastName
                        , payrollRowPayBucket = accumulated.accumulatedPayBucket
                        , payrollRowHours = roundHoursWithResidual exactHours
                        , payrollRowWageCents = map (\slot -> Map.findWithDefault 0 slot accumulated.accumulatedWageCents) hourSlots
                        , payrollRowEntryCount = accumulated.accumulatedEntryCount
                        }

    rowOrder row =
        ( row.payrollRowStaffLastName
        , row.payrollRowStaffFirstName
        , row.payrollRowStaffId
        , row.payrollRowPayBucket.payrollPayBucketLabel
        , row.payrollRowPayBucket.payrollPayBucketKey
        )

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
        , accumulatedEntryCount = existing.accumulatedEntryCount + new.accumulatedEntryCount
        }

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

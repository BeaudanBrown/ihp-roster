-- | Structured export failures stay independent of HTTP and HTML. IDs originate
-- from the caller's authorised entry snapshot, never from a client error string.
module Application.Helper.Export.Failure
    ( ExportFailure (..)
    , ExportEntryFailure (..)
    , collectPayrollTimingFailures
    , loadCheckedExportCalculations
    ) where

import Application.Helper.Export.HourlyBreakdown (wageCentsForEntryBySlot)
import Application.Helper.Export.PayrollWorkbookModel (validateCalculationTiming)
import Application.VenueTime.Model (decodeTimesheetTiming, storedInstantLocalTime)
import Application.WageEngine (WageCalculation)
import Application.WageSourceEnforcement (WageEntryOutcome (..), evaluateDraftWageEntriesAt, finalWageEntryResult, renderWageEntryFailures)
import Application.WageSourcePolicy (PolicyClock (..))
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Generated.Types
import IHP.ControllerPrelude

data ExportFailure
    = ExportMessage Text
    | ExportEntryFailures [ExportEntryFailure]
    deriving (Eq, Show)

data ExportEntryFailure = ExportEntryFailure
    { entryFailureId :: !(Id TimesheetEntry)
    , entryFailureDate :: !Day
    , entryFailureStaffName :: !(Maybe Text)
    , entryFailureStart :: !(Maybe LocalTime)
    , entryFailureEnd :: !(Maybe LocalTime)
    , entryFailureMessage :: !Text
    }
    deriving (Eq, Show)

collectPayrollTimingFailures :: [TimesheetEntry] -> Map.Map UUID Staff -> Map.Map UUID WageCalculation -> [ExportEntryFailure]
collectPayrollTimingFailures entries staffById calculations =
    [ entryFailureFor staffById entry message
    | entry <- entries
    , Left message <- [validate entry]
    ]
  where
    validate entry = do
        case decodeTimesheetTiming entry of
            Left _ -> Left "The recorded shift or break interval is invalid."
            Right _ -> Right ()
        calculation <- maybe (Left "The approved wage calculation is missing.") Right (Map.lookup (unpackId entry.id) calculations)
        validateCalculationTiming entry calculation
        () <$ wageCentsForEntryBySlot entry calculation

entryFailureFor :: Map.Map UUID Staff -> TimesheetEntry -> Text -> ExportEntryFailure
entryFailureFor staffById entry message =
    ExportEntryFailure entry.id entry.operationalDate
        ((\staff -> staff.firstName <> " " <> staff.lastName) <$> Map.lookup entry.staffId staffById)
        (either (const Nothing) Just (storedInstantLocalTime entry.timezone entry.startsAt))
        (either (const Nothing) Just (storedInstantLocalTime entry.timezone entry.endsAt))
        message

-- Evaluate final-pay authority once for the whole snapshot. Keep failures while
-- validating the remaining entries, but never return a partial success.
loadCheckedExportCalculations :: (?modelContext :: ModelContext) =>
    [TimesheetEntry] -> Map.Map UUID Staff -> IO (Either ExportFailure [WageCalculation])
loadCheckedExportCalculations entries staffById = do
    now <- getCurrentTime
    outcomes <- evaluateDraftWageEntriesAt (PolicyClock now) entries
    let results = Map.fromList [(outcome.outcomeEntryId, finalWageEntryResult outcome) | outcome <- outcomes]
        calculations = Map.mapMaybe (either (const Nothing) Just) results
        sourceFailures =
            [ entryFailureFor staffById entry message
            | entry <- entries
            , message <- case Map.lookup (unpackId entry.id) results of
                Nothing -> ["The approved wage calculation is missing."]
                Just (Left failures) -> [renderWageEntryFailures "" failures]
                Just (Right _) -> []
            ]
        validEntries = filter (\entry -> Map.member (unpackId entry.id) calculations) entries
        failures = List.sortOn (\failure -> (failure.entryFailureDate, failure.entryFailureId))
            (sourceFailures <> collectPayrollTimingFailures validEntries staffById calculations)
    pure $ if null failures
        then Right [calculation | entry <- entries, Just calculation <- [Map.lookup (unpackId entry.id) calculations]]
        else Left (ExportEntryFailures failures)


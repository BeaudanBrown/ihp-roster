-- Shared workbook construction for authenticated downloads and background mail.
-- Callers own their consistent entry snapshot and persistence transaction.
module Application.Helper.Export.WorkbookGeneration
    ( GeneratedWorkbook (..)
    , generateWorkbookForVenue
    ) where

import Application.Helper.Export.Failure
import Application.Helper.Export.HourlyBreakdown (buildHourlyShiftTypeColumns)
import Application.Helper.Export.Payloads (calculationMap,
                                           shouldIncludeFixedStaffPayEntry)
import Application.Helper.Export.PayrollWorkbook
import Application.Helper.Export.PayrollWorkbookModel
import Application.Helper.Export.ReadModel
import Application.Helper.Export.XeroPayItems
import Application.Helper.VenueScopedQueries (fetchActiveVenueShiftTypes)
import qualified Data.Bifunctor as Bifunctor
import qualified Data.Map.Strict as Map
import Generated.Types
import IHP.ControllerPrelude

data GeneratedWorkbook = GeneratedWorkbook
    { entries   :: ![TimesheetEntry]
    , manifests :: !(Map.Map UUID Text)
    , facts     :: !PayrollWorkbookFactModel
    , workbook  :: !PayrollWorkbook
    }

generateWorkbookForVenue :: (?modelContext :: ModelContext) =>
    Id Venue -> VenueConfig -> [TimesheetEntry] -> PayrollWorkbookDefinition -> Day -> Day -> IO (Either ExportFailure (Maybe GeneratedWorkbook))
generateWorkbookForVenue venueId config entries definition rangeStart rangeEnd
    | config.venueId /= unpackId venueId || any (\entry -> entry.venueId /= unpackId venueId || not entry.isApproved || isJust entry.deletedAt || entry.operationalDate < rangeStart || entry.operationalDate > rangeEnd) entries =
        pure (Left (ExportMessage "Payroll Workbook entries do not match the approved venue period."))
    | otherwise = do
        staffById <- fetchStaffMap entries
        let included = filter (shouldIncludeFixedStaffPayEntry staffById) entries
        if null included then pure (Right Nothing)
        else loadCheckedExportCalculations included staffById >>= \case
            Left failure -> pure (Left failure)
            Right calculations -> do
                payBuckets <- fetchApprovedEntryPayrollPayBuckets included
                shiftLabels <- fetchApprovedEntryShiftLabels included
                activeShiftTypes <- fetchActiveVenueShiftTypes venueId
                reportShiftTypes <- fetchReportShiftTypes included
                manifests <- fetchVersionManifestsForEntries included
                let columns = buildHourlyShiftTypeColumns activeShiftTypes reportShiftTypes included shiftLabels
                let factsResult = Bifunctor.first ExportMessage (buildPayrollWorkbookFactModel rangeStart rangeEnd config included staffById payBuckets shiftLabels columns (calculationMap included calculations))
                case factsResult of
                    Left failure -> pure (Left failure)
                    Right facts -> do
                        quantities <- if PayrollWorkbookXeroPayItems `elem` definition.payrollWorkbookDefinitionSheetFamilies
                            then fmap Just <$> fetchWorkbookXeroQuantities venueId included
                            else pure (Right Nothing)
                        pure $ Bifunctor.first ExportMessage do
                            resolved <- quantities
                            workbook <- payrollWorkbookFromDefinitionWithXeroQuantities resolved definition config.rosterWeekStartsOn facts
                            Right (Just GeneratedWorkbook { entries = included, manifests, facts, workbook })

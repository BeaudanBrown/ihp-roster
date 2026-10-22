-- Shared workbook construction for authenticated downloads and background mail.
-- Callers own their consistent entry snapshot and persistence transaction.
module Application.Helper.Export.WorkbookGeneration
    ( GeneratedWorkbook (..)
    , generateWorkbookForVenue
    ) where

import Application.Helper.Export.HourlyBreakdown (buildHourlyShiftTypeColumns)
import Application.Helper.Export.Payloads (calculationMap, shouldIncludeFixedStaffPayEntry)
import Application.Helper.Export.PayrollWorkbook
import Application.Helper.Export.PayrollWorkbookModel
import Application.Helper.Export.ReadModel
import Application.Helper.Export.XeroPayItems
import Application.Helper.VenueScopedQueries (fetchActiveVenueShiftTypes)
import Application.WageSourceEnforcement (enforceFinalWageEntries, renderWageEntryFailures)
import qualified Data.Map.Strict as Map
import Generated.Types
import IHP.ControllerPrelude

data GeneratedWorkbook = GeneratedWorkbook
    { entries :: ![TimesheetEntry]
    , manifests :: !(Map.Map UUID Text)
    , facts :: !PayrollWorkbookFactModel
    , workbook :: !PayrollWorkbook
    }

generateWorkbookForVenue :: (?modelContext :: ModelContext) =>
    Id Venue -> VenueConfig -> [TimesheetEntry] -> PayrollWorkbookDefinition -> Day -> Day -> IO (Either Text (Maybe GeneratedWorkbook))
generateWorkbookForVenue venueId config entries definition rangeStart rangeEnd
    | config.venueId /= unpackId venueId || any (\entry -> entry.venueId /= unpackId venueId || not entry.isApproved || isJust entry.deletedAt || entry.operationalDate < rangeStart || entry.operationalDate > rangeEnd) entries =
        pure (Left "Payroll Workbook entries do not match the approved venue period.")
    | otherwise = do
        staffById <- fetchStaffMap entries
        let included = filter (shouldIncludeFixedStaffPayEntry staffById) entries
        if null included then pure (Right Nothing)
        else enforceFinalWageEntries included >>= \case
            Left failures -> pure (Left (renderWageEntryFailures "Payroll Workbook blocked: " failures))
            Right calculations -> do
                payBuckets <- fetchApprovedEntryPayrollPayBuckets included
                shiftLabels <- fetchApprovedEntryShiftLabels included
                activeShiftTypes <- fetchActiveVenueShiftTypes venueId
                reportShiftTypes <- fetchReportShiftTypes included
                manifests <- fetchVersionManifestsForEntries included
                let columns = buildHourlyShiftTypeColumns activeShiftTypes reportShiftTypes included shiftLabels
                case buildPayrollWorkbookFactModel rangeStart rangeEnd config included staffById payBuckets shiftLabels columns (calculationMap included calculations) of
                    Left message -> pure (Left message)
                    Right facts -> do
                        quantities <- if PayrollWorkbookXeroPayItems `elem` definition.payrollWorkbookDefinitionSheetFamilies
                            then fmap Just <$> fetchWorkbookXeroQuantities venueId included
                            else pure (Right Nothing)
                        pure do
                            resolved <- quantities
                            workbook <- payrollWorkbookFromDefinitionWithXeroQuantities resolved definition config.rosterWeekStartsOn facts
                            Right (Just GeneratedWorkbook { entries = included, manifests, facts, workbook })

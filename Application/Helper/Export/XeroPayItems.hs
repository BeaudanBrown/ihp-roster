module Application.Helper.Export.XeroPayItems (fetchWorkbookXeroQuantities, fetchAvailableWorkbookSheetFamilies) where

import Application.Helper.Export.PayrollWorkbook (PayrollWorkbookXeroQuantity (..), PayrollWorkbookSheetFamily (..), availablePayrollWorkbookSheetFamilies)
import Application.WageEngine.Types (WageCalculation (..), EarningsComponent (..))
import Application.WagePublication (datedEarningsComponentsWithOrdinal)
import Application.Xero.Timesheets.Preview
import qualified Data.Map.Strict as Map
import Generated.Types
import IHP.ControllerPrelude

-- Editor availability is deliberately not shift-specific readiness. Existing
-- saved definitions remain intact; generation still validates selected sources.
fetchAvailableWorkbookSheetFamilies :: (?modelContext :: ModelContext) => Id Venue -> IO [PayrollWorkbookSheetFamily]
fetchAvailableWorkbookSheetFamilies venueId = do
    connection <- query @XeroConnection
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#connectionStatus, "active")
        |> filterWhere (#disconnectedAt, Nothing)
        |> fetchOneOrNothing
    hasPayItems <- case connection of
        Nothing -> pure False
        Just connection -> query @XeroEarningsRate
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#providerAvailable, True)
            |> fetchExists
    pure (filter (\family -> family /= PayrollWorkbookXeroPayItems || hasPayItems) availablePayrollWorkbookSheetFamilies)

-- Read-only: exports consume approval routing or already-established bindings;
-- they never provision pay items, verify employee mappings, or call Xero.
fetchWorkbookXeroQuantities :: (?modelContext :: ModelContext) => Id Venue -> Day -> Day -> [TimesheetEntry] -> IO (Either Text [PayrollWorkbookXeroQuantity])
fetchWorkbookXeroQuantities venueId start end entries = do
    connection <- query @XeroConnection
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#connectionStatus, "active")
        |> filterWhere (#disconnectedAt, Nothing)
        |> fetchOneOrNothing
    case connection of
        Nothing -> pure (Left "Xero pay-items sheet requires a connected Xero organisation and resolved pay items.")
        Just connection -> do
            input <- fetchEarningsInputForEntries venueId start end connection entries
            rates <- query @XeroEarningsRate |> filterWhere (#xeroConnectionId, unpackId connection.id) |> fetch
            employees <- query @XeroEmployee |> filterWhere (#xeroConnectionId, unpackId connection.id) |> fetch
            pure (concat <$> mapM (entryQuantities input rates employees) entries)

entryQuantities :: XeroTimesheetPreviewInput -> [XeroEarningsRate] -> [XeroEmployee] -> TimesheetEntry -> Either Text [PayrollWorkbookXeroQuantity]
entryQuantities input rates employees entry = do
    staff <- require "staff record" (find ((== entry.staffId) . unpackId . (.id)) input.previewStaff)
    staffVersion <- require "approved staff pay version" entry.staffPayVersionId
    shiftVersion <- require "approved shift pay version" entry.shiftTypePayVersionId
    calculation <- require "sealed calculation" (Map.lookup (unpackId entry.id) input.previewCalculationsByEntryId)
    payCalculation <- require "sealed Operational-date facts" (Map.lookup (unpackId entry.id) input.previewPayCalculationsByEntryId)
    unless (calculation.publishedOperationalDate == Just entry.operationalDate && payCalculation.operationalDate == entry.operationalDate)
        (Left (entryMessage "sealed Operational-date mismatch"))
    components <- require "sealed component rows" (Map.lookup (unpackId payCalculation.id) input.previewComponentRowsByCalculationId)
    forM (filter (\(_, _, component) -> component.quantity > 0) (datedEarningsComponentsWithOrdinal calculation)) \(ordinal, componentDate, component) -> do
        componentRow <- require "sealed component ordinal" (find ((== ordinal) . (.ordinal)) components)
        (_, rateId) <- resolveComponentEarningsRouting input payCalculation entry staff staffVersion shiftVersion componentRow componentDate component
        rate <- require ("Xero pay item " <> rateId <> "; sync and resolve pay items in Xero preparation") (find ((== rateId) . (.xeroEarningsRateId)) rates)
        let bepisName = staff.firstName <> " " <> staff.lastName
            employee = do
                mapping <- find ((== entry.staffId) . (.staffId)) input.previewStaffMappings
                employeeId <- mapping.xeroEmployeeId
                find ((== employeeId) . (.xeroEmployeeId)) employees
            xeroName = (.displayName) <$> employee
            displayName = case xeroName of
                Just name | name /= bepisName -> bepisName <> " (" <> name <> ")"
                _ -> bepisName
        pure PayrollWorkbookXeroQuantity
            { xeroQuantityStaffId = entry.staffId
            , xeroQuantityStaffName = displayName
            , xeroQuantityPayItemId = rateId
            , xeroQuantityPayItemName = rate.name
            , xeroQuantityDate = payCalculation.operationalDate
            , xeroQuantityUnits = component.quantity
            }
  where
    entryMessage detail = "Xero pay-items sheet blocked for shift " <> tshow (unpackId entry.id) <> ": " <> detail <> "."
    require :: Text -> Maybe value -> Either Text value
    require detail = maybe (Left (entryMessage ("Missing " <> detail))) Right

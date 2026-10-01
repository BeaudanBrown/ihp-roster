module Application.Helper.Export.XeroPayItems (fetchWorkbookXeroQuantities) where

import Application.Helper.Export.PayrollWorkbook (PayrollWorkbookXeroQuantity (..))
import Application.Helper.TimesheetPayLedger (loadApprovedTimesheetPayCalculationResults)
import Application.Helper.XeroPayItems (xeroPayItemNameForComponent)
import Application.WageEngine.Types (WageCalculation (..), EarningsComponent (..), SourceCondition (..))
import Application.WagePublication (datedEarningsComponents)
import Application.Xero.Timesheets.BucketKey
import qualified Data.Map.Strict as Map
import Generated.Types
import IHP.ControllerPrelude

-- Manual entry needs local pay-item names and sealed quantities, not a provider
-- connection, employee mapping, earnings-rate ID or upload-time late binding.
fetchWorkbookXeroQuantities :: (?modelContext :: ModelContext) => Id Venue -> [TimesheetEntry] -> IO (Either Text [PayrollWorkbookXeroQuantity])
fetchWorkbookXeroQuantities venueId entries = do
    staff <- query @Staff |> filterWhere (#venueId, unpackId venueId) |> filterWhereIn (#id, map (Id . (.staffId)) entries) |> fetch
    staffVersions <- query @StaffPayVersion |> filterWhereIn (#id, mapMaybe (fmap Id . (.staffPayVersionId)) entries) |> fetch
    shiftVersions <- query @ShiftTypePayVersion |> filterWhereIn (#id, mapMaybe (fmap Id . (.shiftTypePayVersionId)) entries) |> fetch
    levels <- query @AwardLevel |> fetch
    imported <- query @XeroImportedPayItem |> filterWhere (#venueId, unpackId venueId)
        |> filterWhereIn (#id, mapMaybe (.importedXeroPayItemId) staffVersions <> mapMaybe (.importedXeroPayItemId) shiftVersions) |> fetch
    payCalculations <- query @TimesheetPayCalculation |> filterWhereIn (#id, mapMaybe (.activePayCalculationId) entries) |> fetch
    loaded <- loadApprovedTimesheetPayCalculationResults entries
    let context = XeroComponentBucketContext
            { bucketStaffPayVersions = Map.fromList [(unpackId version.id, version) | version <- staffVersions]
            , bucketShiftTypePayVersions = Map.fromList [(unpackId version.id, version) | version <- shiftVersions]
            , bucketAwardLevels = levels
            }
    pure $ fmap concat $ forM entries \entry -> do
        let require :: Text -> Maybe value -> Either Text value
            require detail = maybe (Left ("Xero pay-items sheet: missing " <> detail <> " for shift " <> tshow (unpackId entry.id))) Right
        unless (entry.venueId == unpackId venueId) (Left "Xero pay-items sheet contains a foreign shift.")
        person <- require "staff record" (find ((== entry.staffId) . unpackId . (.id)) staff)
        calculation <- case Map.lookup (unpackId entry.id) loaded of
            Just (Right (Just value)) -> Right value
            _ -> Left ("Xero pay-items sheet: invalid approved pay ledger for shift " <> tshow (unpackId entry.id))
        payCalculation <- require "sealed Operational-date facts" (find ((== entry.activePayCalculationId) . Just . (.id)) payCalculations)
        unless (entry.isApproved && isNothing entry.deletedAt
                && payCalculation.timesheetEntryId == unpackId entry.id
                && Just payCalculation.staffPayVersionId == entry.staffPayVersionId
                && Just payCalculation.shiftTypePayVersionId == entry.shiftTypePayVersionId
                && Just payCalculation.approvedAt == entry.approvedAt
                && Just payCalculation.approvedByUserId == entry.approvedByUserId)
            (Left "Xero pay-items sheet: approved pay-version or approval provenance mismatch.")
        unless (calculation.publishedOperationalDate == Just entry.operationalDate && payCalculation.operationalDate == entry.operationalDate)
            (Left "Xero pay-items sheet: sealed Operational-date mismatch.")
        forM (filter ((> 0) . (.quantity) . snd) (datedEarningsComponents calculation)) \(componentDate, component) -> do
            key <- componentBucketKey payCalculation.rosterWeekStartsOn context entry person component componentDate
            staffVersion <- require "approved staff pay version" (entry.staffPayVersionId >>= (`Map.lookup` context.bucketStaffPayVersions))
            shiftVersion <- require "approved shift pay version" (entry.shiftTypePayVersionId >>= (`Map.lookup` context.bucketShiftTypePayVersions))
            name <- case component.sourceCondition of
                ImportedFlatRateCondition itemId -> do
                    pinnedId <- require "approved imported pay-item identity" (shiftVersion.importedXeroPayItemId <|> staffVersion.importedXeroPayItemId)
                    unless (inputValue pinnedId == itemId) (Left "Xero pay-items sheet: imported component does not match the approved pay version.")
                    item <- require "approval-pinned imported pay item" (find ((== pinnedId) . (.id)) imported)
                    Right item.name
                _ -> do
                    levelId <- require "approved Award classification" (shiftVersion.overrideAwardLevelId <|> staffVersion.defaultAwardLevelId)
                    level <- require "Award classification" (find ((== levelId) . unpackId . (.id)) levels)
                    xeroPayItemNameForComponent level.classification staffVersion.employmentBasis component
            pure PayrollWorkbookXeroQuantity
                { xeroQuantityStaffId = entry.staffId
                , xeroQuantityStaffName = person.firstName <> " " <> person.lastName
                , xeroQuantityPayItemId = key
                , xeroQuantityPayItemName = name
                -- The selected Operational date owns the complete overnight
                -- entry, including components beyond the export's final date.
                , xeroQuantityDate = payCalculation.operationalDate
                , xeroQuantityUnits = component.quantity
                }

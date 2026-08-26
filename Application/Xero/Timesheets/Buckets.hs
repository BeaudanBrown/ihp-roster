module Application.Xero.Timesheets.Buckets
    ( module Application.Xero.Timesheets.BucketKey
    , fetchPeriodXeroLocalEarningsBuckets
    , fetchPeriodXeroLocalEarningsBucketsExcludingEntries
    ) where

import Application.Helper.TimesheetPayLedger (loadApprovedTimesheetPayCalculations)
import Application.Helper.XeroAdminTypes
import Application.WageEngine.Types (EarningsComponent (..))
import Application.WagePublication (datedEarningsComponents)
import Application.Xero.Timesheets.BucketKey
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Time.Calendar (Day, addDays)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (unpackId)

fetchPeriodXeroLocalEarningsBuckets ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Day ->
    Day ->
    [UUID] ->
    IO (Either Text [XeroLocalEarningsBucket])
fetchPeriodXeroLocalEarningsBuckets venueId periodStart periodEnd skippedStaffIds =
    fetchPeriodXeroLocalEarningsBucketsExcludingEntries venueId periodStart periodEnd skippedStaffIds []

fetchPeriodXeroLocalEarningsBucketsExcludingEntries ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Day ->
    Day ->
    [UUID] ->
    [UUID] ->
    IO (Either Text [XeroLocalEarningsBucket])
fetchPeriodXeroLocalEarningsBucketsExcludingEntries venueId periodStart periodEnd skippedStaffIds excludedEntryIds = do
    approvedEntries <-
        query @TimesheetEntry
            |> filterWhere (#venueId, unpackId venueId)
            |> filterWhereGreaterThanOrEqualTo (#operationalDate, periodStart)
            |> filterWhereLessThan (#operationalDate, addDays 1 periodEnd)
            |> filterWhere (#isApproved, True)
            |> filterWhere (#deletedAt, Nothing)
            |> orderBy #operationalDate
            |> orderBy #startsAt
            |> fetch
    let entries =
            approvedEntries
                |> filter (not . (`elem` skippedStaffIds) . (.staffId))
                |> filter (not . (`elem` excludedEntryIds) . unpackId . (.id))
    staffMembers <- query @Staff |> filterWhere (#venueId, unpackId venueId) |> filterWhereIn (#id, map (Id . (.staffId)) entries) |> fetch
    staffPayVersions <- query @StaffPayVersion |> filterWhereIn (#id, mapMaybe (fmap Id . (.staffPayVersionId)) entries) |> fetch
    shiftTypePayVersions <- query @ShiftTypePayVersion |> filterWhereIn (#id, mapMaybe (fmap Id . (.shiftTypePayVersionId)) entries) |> fetch
    payCalculations <- query @TimesheetPayCalculation
        |> filterWhereIn (#id, mapMaybe (.activePayCalculationId) entries)
        |> fetch
    awardLevels <- query @AwardLevel |> fetch
    loadedCalculations <- loadApprovedTimesheetPayCalculations entries
    pure do
        entryCalculations <- forM entries \entry ->
            case Map.lookup (unpackId entry.id) loadedCalculations of
                Nothing -> Left ("Approved entry ledger result was not loaded: " <> tshow (unpackId entry.id))
                Just (Left message) -> Left message
                Just (Right Nothing) -> Left ("Approved entry has no sealed calculation: " <> tshow (unpackId entry.id))
                Just (Right (Just result)) -> Right (entry, result)
        let staffMap = Map.fromList [(unpackId staff.id, staff) | staff <- staffMembers]
            payCalculationsByEntryId = Map.fromList [(calculation.timesheetEntryId, calculation) | calculation <- payCalculations]
            context = XeroComponentBucketContext
                { bucketStaffPayVersions = Map.fromList [(unpackId version.id, version) | version <- staffPayVersions]
                , bucketShiftTypePayVersions = Map.fromList [(unpackId version.id, version) | version <- shiftTypePayVersions]
                , bucketAwardLevels = awardLevels
                }
        buckets <- fmap concat $ forM entryCalculations \(entry, calculation) -> do
            staff <- maybeToEither ("Missing staff for approved entry " <> tshow (unpackId entry.id)) (Map.lookup entry.staffId staffMap)
            payCalculation <- maybeToEither ("Missing sealed Operational-window facts for approved entry " <> tshow (unpackId entry.id)) (Map.lookup (unpackId entry.id) payCalculationsByEntryId)
            forM (datedEarningsComponents calculation) \(componentDate, component@EarningsComponent { publishedXeroLocalBucketKey, publishedXeroEarningsRateId }) -> do
                key <- case (publishedXeroLocalBucketKey, publishedXeroEarningsRateId) of
                    (Just sealedBucketKey, Just _) -> pure sealedBucketKey
                    (Nothing, Nothing) -> componentBucketKey payCalculation.rosterWeekStartsOn context entry staff component componentDate
                    _ -> Left ("Approved component has an incomplete sealed Xero earnings mapping for entry " <> tshow (unpackId entry.id))
                pure XeroLocalEarningsBucket { localBucketKey = key, localBucketLabel = key }
        pure (dedupeBuckets buckets)


dedupeBuckets :: [XeroLocalEarningsBucket] -> [XeroLocalEarningsBucket]
dedupeBuckets =
    mapMaybe listToMaybe
        . List.groupBy (\left right -> left.localBucketKey == right.localBucketKey)
        . List.sortOn (.localBucketKey)

maybeToEither :: Text -> Maybe value -> Either Text value
maybeToEither message = maybe (Left message) Right

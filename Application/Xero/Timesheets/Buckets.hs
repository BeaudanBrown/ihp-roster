module Application.Xero.Timesheets.Buckets
    ( module Application.Xero.Timesheets.BucketKey
    , XeroAvailableBuckets (..)
    , XeroBucketError (..)
    , XeroBucketOutcome (..)
    , XeroBucketProblem (..)
    , bucketErrorCode
    , bucketErrorSafeMessage
    , fetchPeriodXeroLocalEarningsBuckets
    , fetchPeriodXeroLocalEarningsBucketsExcludingEntries
    ) where

import Application.Error.Types (AppResult)
import Application.Helper.Telemetry (addTelemetryEvent)
import Application.Helper.TimesheetPayLedger (ApprovedPayLedgerError (..),
                                              loadApprovedTimesheetPayCalculationResults)
import Application.Helper.XeroAdminTypes
import Application.WageEngine.Types (EarningsComponent (..), WageCalculation)
import Application.WagePublication (datedEarningsComponents)
import Application.Xero.Timesheets.BucketKey
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (unpackId)
import OpenTelemetry.Attributes (toAttribute)

data XeroBucketError
    = XeroBucketPayLedgerError !ApprovedPayLedgerError
    | XeroBucketMissingSealedCalculation
    | XeroBucketMissingStaff
    | XeroBucketMissingOperationalWindowFacts
    | XeroBucketKeyDerivationFailed !Text
    | XeroBucketMissingSealedEarningsMapping
    | XeroBucketIncompleteSealedEarningsMapping
    deriving (Eq, Show)

data XeroBucketProblem = XeroBucketProblem
    { xeroBucketProblemEntryId :: !UUID
    , xeroBucketProblemCause   :: !XeroBucketError
    }
    deriving (Eq, Show)

data XeroAvailableBuckets = XeroAvailableBuckets
    { xeroAvailableBucketValues        :: ![XeroLocalEarningsBucket]
    , xeroAvailableBucketEntryIdsByKey :: !(Map.Map Text [UUID])
    }

data XeroBucketOutcome
    = XeroBucketsAvailable !XeroAvailableBuckets
    | XeroBucketsBlocked ![XeroBucketProblem]

bucketErrorCode :: XeroBucketError -> Text
bucketErrorCode = \case
    XeroBucketPayLedgerError _              -> "approved_pay_ledger_invalid"
    XeroBucketMissingSealedCalculation      -> "approved_pay_ledger_missing"
    XeroBucketMissingStaff                  -> "approved_entry_staff_missing"
    XeroBucketMissingOperationalWindowFacts -> "approved_operational_facts_missing"
    XeroBucketKeyDerivationFailed _         -> "approved_bucket_key_invalid"
    XeroBucketMissingSealedEarningsMapping  -> "approved_xero_mapping_missing"
    XeroBucketIncompleteSealedEarningsMapping -> "approved_xero_mapping_incomplete"

bucketErrorSafeMessage :: XeroBucketError -> Text
bucketErrorSafeMessage = \case
    XeroBucketPayLedgerError _ -> "The approved pay ledger is incomplete or invalid."
    XeroBucketMissingSealedCalculation -> "The approved timesheet has no sealed pay calculation."
    XeroBucketMissingStaff -> "The approved timesheet no longer has a trustworthy staff record."
    XeroBucketMissingOperationalWindowFacts -> "The approved timesheet is missing sealed operational-window facts."
    XeroBucketKeyDerivationFailed _ -> "The approved pay ledger cannot be assigned to a Xero pay bucket."
    XeroBucketMissingSealedEarningsMapping -> "The approved pay ledger has no sealed Xero earnings mapping; unapprove and reapprove the timesheet after mappings are ready."
    XeroBucketIncompleteSealedEarningsMapping -> "The approved pay ledger has an incomplete sealed Xero earnings mapping; unapprove and reapprove the timesheet after mappings are ready."

fetchPeriodXeroLocalEarningsBuckets ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Day ->
    Day ->
    [UUID] ->
    IO (AppResult XeroBucketOutcome)
fetchPeriodXeroLocalEarningsBuckets venueId periodStart periodEnd skippedStaffIds =
    fetchPeriodXeroLocalEarningsBucketsExcludingEntries venueId periodStart periodEnd skippedStaffIds []

fetchPeriodXeroLocalEarningsBucketsExcludingEntries ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Day ->
    Day ->
    [UUID] ->
    [UUID] ->
    IO (AppResult XeroBucketOutcome)
fetchPeriodXeroLocalEarningsBucketsExcludingEntries venueId periodStart periodEnd skippedStaffIds excludedEntryIds =
    Right <$> fetchBuckets
  where
    fetchBuckets = do
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
        loadedCalculations <- loadApprovedTimesheetPayCalculationResults entries
        let staffMap = Map.fromList [(unpackId staff.id, staff) | staff <- staffMembers]
            payCalculationsByEntryId = Map.fromList [(calculation.timesheetEntryId, calculation) | calculation <- payCalculations]
            context = XeroComponentBucketContext
                { bucketStaffPayVersions = Map.fromList [(unpackId version.id, version) | version <- staffPayVersions]
                , bucketShiftTypePayVersions = Map.fromList [(unpackId version.id, version) | version <- shiftTypePayVersions]
                , bucketAwardLevels = awardLevels
                }
        let results = map (entryBuckets loadedCalculations staffMap payCalculationsByEntryId context) entries
            problems = concatMap fst results
            buckets = concatMap snd results
            entryIdsByKey = Map.fromListWith (<>)
                [ (bucket.localBucketKey, [unpackId entry.id])
                | (entry, (_, entryBucketsForEntry)) <- zip entries results
                , bucket <- entryBucketsForEntry
                ]
        if null problems
            then pure (XeroBucketsAvailable XeroAvailableBuckets
                { xeroAvailableBucketValues = dedupeBuckets buckets
                , xeroAvailableBucketEntryIdsByKey = fmap List.nub entryIdsByKey
                })
            else do
                addTelemetryEvent
                    "xero.timesheets.bucket_blocked"
                    [ ("xero.operation_code", toAttribute ("xero.timesheets.prepare" :: Text))
                    , ("xero.bucket.problem_count", toAttribute (length problems))
                    , ("xero.bucket.cause_codes", toAttribute (Text.intercalate "," (List.nub (map (bucketErrorCode . (.xeroBucketProblemCause)) problems))))
                    ]
                pure (XeroBucketsBlocked problems)

entryBuckets ::
    Map.Map UUID (Either ApprovedPayLedgerError (Maybe WageCalculation)) ->
    Map.Map UUID Staff ->
    Map.Map UUID TimesheetPayCalculation ->
    XeroComponentBucketContext ->
    TimesheetEntry ->
    ([XeroBucketProblem], [XeroLocalEarningsBucket])
entryBuckets loadedCalculations staffMap payCalculationsByEntryId context entry =
    case Map.lookup entryId loadedCalculations of
        Nothing -> blocked (XeroBucketPayLedgerError ApprovedPayLedgerResultNotLoaded)
        Just (Left cause) -> blocked (XeroBucketPayLedgerError cause)
        Just (Right Nothing) -> blocked XeroBucketMissingSealedCalculation
        Just (Right (Just calculation)) ->
            case (Map.lookup entry.staffId staffMap, Map.lookup entryId payCalculationsByEntryId) of
                (Nothing, Nothing) -> blockedMany [XeroBucketMissingStaff, XeroBucketMissingOperationalWindowFacts]
                (Nothing, Just _) -> blocked XeroBucketMissingStaff
                (Just _, Nothing) -> blocked XeroBucketMissingOperationalWindowFacts
                (Just staff, Just payCalculation) ->
                    let componentResults = map (componentBucket payCalculation staff) (datedEarningsComponents calculation)
                     in (concatMap fst componentResults, concatMap snd componentResults)
  where
    entryId = unpackId entry.id
    problem cause = XeroBucketProblem entryId cause
    blocked cause = ([problem cause], [])
    blockedMany causes = (map problem causes, [])
    componentBucket payCalculation staff (componentDate, component@EarningsComponent { publishedXeroLocalBucketKey, publishedXeroEarningsRateId }) =
        case (publishedXeroLocalBucketKey, publishedXeroEarningsRateId) of
            (Just sealedBucketKey, Just _) -> ([], [XeroLocalEarningsBucket sealedBucketKey sealedBucketKey])
            (Nothing, Nothing) ->
                case componentBucketKey payCalculation.rosterWeekStartsOn context entry staff component componentDate of
                    Left message -> blocked (XeroBucketKeyDerivationFailed message)
                    Right key    -> ([], [XeroLocalEarningsBucket key key])
            _ -> blocked XeroBucketIncompleteSealedEarningsMapping

dedupeBuckets :: [XeroLocalEarningsBucket] -> [XeroLocalEarningsBucket]
dedupeBuckets =
    mapMaybe listToMaybe
        . List.groupBy (\left right -> left.localBucketKey == right.localBucketKey)
        . List.sortOn (.localBucketKey)

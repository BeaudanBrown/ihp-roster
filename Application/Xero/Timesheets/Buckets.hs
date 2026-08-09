module Application.Xero.Timesheets.Buckets
    ( XeroComponentBucketContext (..)
    , componentBucketKey
    , fetchPeriodXeroLocalEarningsBuckets
    , fetchPeriodXeroLocalEarningsBucketsExcludingEntries
    ) where

import Application.Helper.Pay (venueEffectiveRateDate)
import Application.Helper.TimesheetPayLedger (loadApprovedTimesheetPayCalculations)
import Application.Helper.WeekBoundaries (WeekdayIndex)
import Application.Helper.XeroAdminTypes
import Application.VenueTime.Model (requireMelbourneDateRangeUTC)
import Application.WageEngine
import Application.WagePublication (datedEarningsComponents)
import Application.Xero.PayrollSourceKey (sourceRateSuffix)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Time.Calendar (Day)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (inputValue, unpackId)

data XeroComponentBucketContext = XeroComponentBucketContext
    { bucketRosterWeekStartsOn    :: !WeekdayIndex
    , bucketStaffPayVersions      :: !(Map.Map UUID StaffPayVersion)
    , bucketShiftTypePayVersions  :: !(Map.Map UUID ShiftTypePayVersion)
    , bucketAwardLevels           :: ![AwardLevel]
    , bucketAwardLevelBaseRates   :: ![AwardLevelBaseRate]
    , bucketAwardLevelPenalties   :: ![AwardLevelPenaltyRate]
    , bucketTimePenaltyAllowances :: ![AwardTimePenaltyAllowance]
    }

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
    let (periodStartsAt, periodEndsAt) = requireMelbourneDateRangeUTC periodStart periodEnd
    approvedEntries <-
        query @TimesheetEntry
            |> filterWhere (#venueId, unpackId venueId)
            |> filterWhereGreaterThanOrEqualTo (#startsAt, periodStartsAt)
            |> filterWhereLessThan (#startsAt, periodEndsAt)
            |> filterWhere (#isApproved, True)
            |> filterWhere (#deletedAt, Nothing)
            |> orderBy #startsAt
            |> fetch
    let entries =
            approvedEntries
                |> filter (not . (`elem` skippedStaffIds) . (.staffId))
                |> filter (not . (`elem` excludedEntryIds) . unpackId . (.id))
    staffMembers <- query @Staff |> filterWhere (#venueId, unpackId venueId) |> filterWhereIn (#id, map (Id . (.staffId)) entries) |> fetch
    staffPayVersions <- query @StaffPayVersion |> filterWhereIn (#id, mapMaybe (fmap Id . (.staffPayVersionId)) entries) |> fetch
    shiftTypePayVersions <- query @ShiftTypePayVersion |> filterWhereIn (#id, mapMaybe (fmap Id . (.shiftTypePayVersionId)) entries) |> fetch
    venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venueId) |> fetchOne
    awardLevels <- query @AwardLevel |> fetch
    baseRates <- query @AwardLevelBaseRate |> fetch
    penaltyRates <- query @AwardLevelPenaltyRate |> fetch
    timeAllowances <- query @AwardTimePenaltyAllowance |> fetch
    loadedCalculations <- loadApprovedTimesheetPayCalculations entries
    pure do
        entryCalculations <- forM entries \entry ->
            case Map.lookup (unpackId entry.id) loadedCalculations of
                Nothing -> Left ("Approved entry ledger result was not loaded: " <> tshow (unpackId entry.id))
                Just (Left message) -> Left message
                Just (Right Nothing) -> Left ("Approved entry has no sealed calculation: " <> tshow (unpackId entry.id))
                Just (Right (Just result)) -> Right (entry, result)
        let staffMap = Map.fromList [(unpackId staff.id, staff) | staff <- staffMembers]
            context = XeroComponentBucketContext
                { bucketRosterWeekStartsOn = venueConfig.rosterWeekStartsOn
                , bucketStaffPayVersions = Map.fromList [(unpackId version.id, version) | version <- staffPayVersions]
                , bucketShiftTypePayVersions = Map.fromList [(unpackId version.id, version) | version <- shiftTypePayVersions]
                , bucketAwardLevels = awardLevels
                , bucketAwardLevelBaseRates = baseRates
                , bucketAwardLevelPenalties = penaltyRates
                , bucketTimePenaltyAllowances = timeAllowances
                }
        buckets <- fmap concat $ forM entryCalculations \(entry, calculation) -> do
            staff <- maybeToEither ("Missing staff for approved entry " <> tshow (unpackId entry.id)) (Map.lookup entry.staffId staffMap)
            forM (datedEarningsComponents calculation) \(componentDate, component) -> do
                key <- componentBucketKey context entry staff component componentDate
                pure XeroLocalEarningsBucket { localBucketKey = key, localBucketLabel = key }
        pure (dedupeBuckets buckets)

componentBucketKey :: XeroComponentBucketContext -> TimesheetEntry -> Staff -> EarningsComponent -> Day -> Either Text Text
componentBucketKey context entry staff component componentDate =
    case component.sourceCondition of
        ImportedFlatRateCondition itemId ->
            pure ("xero:imported-pay-item:" <> itemId)
        condition -> do
            staffVersionId <- maybeToEither "Missing approved staff pay version." entry.staffPayVersionId
            shiftVersionId <- maybeToEither "Missing approved shift pay version." entry.shiftTypePayVersionId
            staffVersion <- maybeToEither "Approved staff pay version was not loaded." (Map.lookup staffVersionId context.bucketStaffPayVersions)
            shiftVersion <- maybeToEither "Approved shift pay version was not loaded." (Map.lookup shiftVersionId context.bucketShiftTypePayVersions)
            payLevelId <- maybeToEither "Missing approved Award classification." (shiftVersion.overrideAwardLevelId <|> staffVersion.defaultAwardLevelId)
            awardLevel <- maybeToEither "Approved Award classification was not loaded." (find (\level -> unpackId level.id == payLevelId) context.bucketAwardLevels)
            effectiveFrom <- effectiveDateFor context awardLevel payLevelId staffVersion.employmentBasis component
            let classificationPrefix = "xero:pay-item:classification:" <> tshow awardLevel.classificationFixedId
                effectivePart = ":effective:" <> maybe "undated" tshow (venueEffectiveRateDate context.bucketRosterWeekStartsOn <$> effectiveFrom)
                sourceSuffix = sourceRateSuffix component.sourceRateIdentity component.ratePerUnit
            pure $ case condition of
                MissedMealBreakAdditionCondition -> classificationPrefix <> effectivePart <> ":penalty:missed_meal_break_addition" <> sourceSuffix
                _ -> classificationPrefix <> ":basis:" <> inputValue staffVersion.employmentBasis <> effectivePart <> ":" <> conditionKey condition <> sourceSuffix

effectiveDateFor :: XeroComponentBucketContext -> AwardLevel -> UUID -> StaffEmploymentBasisEnum -> EarningsComponent -> Either Text (Maybe Day)
effectiveDateFor context awardLevel payLevelId employmentBasis component =
    case component.sourceCondition of
        OrdinaryCondition                -> base employmentBasis
        MissedMealBreakAdditionCondition -> missedBreakBase
        SaturdayCondition                -> penalty SaturdayPenalty
        SundayCondition                  -> penalty SundayPenalty
        PublicHolidayCondition           -> penalty PublicHolidayPenalty
        EveningAdditionCondition         -> allowance EveningAfter7Pm
        EarlyMorningAdditionCondition    -> allowance LateNightAfterMidnight
        ImportedFlatRateCondition _      -> Right Nothing
  where
    base basis =
        context.bucketAwardLevelBaseRates
            |> find (\rate -> rate.awardLevelId == payLevelId && rate.employmentBasis == basis && sourceProjectionMatches component (AwardLevelBaseRateSource (unpackId rate.id) rate.fwcMapdPayRateId))
            |> fmap (.operativeFrom)
            |> maybeToEither "Missing approval-pinned base-rate source."
    missedBreakBase =
        context.bucketAwardLevelBaseRates
            |> find (\rate -> rate.awardLevelId == payLevelId && rate.employmentBasis == Permanent && sourceProjectionMatches component (AwardLevelBaseRateSource (unpackId rate.id) rate.fwcMapdPayRateId))
            |> fmap (.operativeFrom)
            |> maybeToEither "Missing approval-pinned base-rate source."
    penalty kind =
        context.bucketAwardLevelPenalties
            |> find (\rate -> rate.awardLevelId == payLevelId && rate.employmentBasis == employmentBasis && rate.penaltyKind == kind && sourceProjectionMatches component (AwardLevelPenaltyRateSource (unpackId rate.id) rate.fwcMapdPenaltyRateId))
            |> fmap (.operativeFrom)
            |> maybeToEither "Missing approval-pinned penalty-rate source."
    allowance kind =
        context.bucketTimePenaltyAllowances
            |> find (\item -> item.awardFixedId == awardLevel.awardFixedId && item.penaltyKind == kind && sourceProjectionMatches component (AwardTimePenaltyAllowanceSource (unpackId item.id) item.fwcMapdWageAllowanceId))
            |> fmap (.operativeFrom)
            |> maybeToEither "Missing approval-pinned fixed-addition source."

sourceProjectionMatches :: EarningsComponent -> ProjectionRateSource -> Bool
sourceProjectionMatches component projection =
    maybe False (rateSourceIdentityReferencesProjection projection) component.sourceRateIdentity

conditionKey :: SourceCondition -> Text
conditionKey = \case
    OrdinaryCondition                -> "ordinary"
    SaturdayCondition                -> "penalty:saturday_penalty"
    SundayCondition                  -> "penalty:sunday_penalty"
    PublicHolidayCondition           -> "penalty:public_holiday_penalty"
    EveningAdditionCondition         -> "penalty:evening_after_7pm"
    EarlyMorningAdditionCondition    -> "penalty:late_night_after_midnight"
    MissedMealBreakAdditionCondition -> "penalty:missed_meal_break_addition"
    ImportedFlatRateCondition itemId -> "imported:" <> itemId

dedupeBuckets :: [XeroLocalEarningsBucket] -> [XeroLocalEarningsBucket]
dedupeBuckets =
    mapMaybe listToMaybe
        . List.groupBy (\left right -> left.localBucketKey == right.localBucketKey)
        . List.sortOn (.localBucketKey)

maybeToEither :: Text -> Maybe value -> Either Text value
maybeToEither message = maybe (Left message) Right

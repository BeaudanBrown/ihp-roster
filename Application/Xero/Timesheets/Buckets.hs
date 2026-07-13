module Application.Xero.Timesheets.Buckets
    ( fetchPeriodXeroLocalEarningsBuckets
    ) where

import Application.Helper.Pay
import Application.Helper.WeekBoundaries (WeekdayIndex)
import Application.Helper.XeroAdminTypes
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (inputValue, unpackId)

fetchPeriodXeroLocalEarningsBuckets ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Day ->
    Day ->
    [UUID] ->
    IO [XeroLocalEarningsBucket]
fetchPeriodXeroLocalEarningsBuckets venueId periodStart periodEnd skippedStaffIds = do
    approvedEntries <-
        query @TimesheetEntry
            |> filterWhere (#venueId, unpackId venueId)
            |> filterWhereGreaterThanOrEqualTo (#workedOn, periodStart)
            |> filterWhereLessThanOrEqualTo (#workedOn, periodEnd)
            |> filterWhere (#isApproved, True)
            |> filterWhere (#deletedAt, Nothing)
            |> orderBy #workedOn
            |> fetch
    let entries = filter (not . (`elem` skippedStaffIds) . (.staffId)) approvedEntries
    staffMembers <-
        query @Staff
            |> filterWhere (#venueId, unpackId venueId)
            |> filterWhereIn (#id, map (Id . (.staffId)) entries)
            |> fetch
    staffPayVersions <-
        query @StaffPayVersion
            |> filterWhereIn (#id, mapMaybe (fmap Id . (.staffPayVersionId)) entries)
            |> fetch
    shiftTypePayVersions <-
        query @ShiftTypePayVersion
            |> filterWhereIn (#id, mapMaybe (fmap Id . (.shiftTypePayVersionId)) entries)
            |> fetch
    venueConfig <-
        query @VenueConfig
            |> filterWhere (#venueId, unpackId venueId)
            |> fetchOne
    payResults <- fetchTimesheetPayResultsForEntries entries
    awardLevels <- query @AwardLevel |> fetch
    baseRates <- query @AwardLevelBaseRate |> fetch
    penaltyRates <- query @AwardLevelPenaltyRate |> fetch
    timeAllowances <- query @AwardTimePenaltyAllowance |> fetch
    let buckets = concatMap (entryBuckets venueConfig.rosterWeekStartsOn staffMembers staffPayVersions shiftTypePayVersions payResults awardLevels baseRates penaltyRates timeAllowances) entries
    pure (dedupeBuckets buckets)

entryBuckets ::
    WeekdayIndex ->
    [Staff] ->
    [StaffPayVersion] ->
    [ShiftTypePayVersion] ->
    Map.Map Text TimesheetPayResult ->
    [AwardLevel] ->
    [AwardLevelBaseRate] ->
    [AwardLevelPenaltyRate] ->
    [AwardTimePenaltyAllowance] ->
    TimesheetEntry ->
    [XeroLocalEarningsBucket]
entryBuckets weekStartsOn staffMembers staffPayVersions shiftTypePayVersions payResults awardLevels baseRates penaltyRates timeAllowances entry
    | entryUsesImportedPayItem staffPayVersions shiftTypePayVersions entry = []
    | otherwise =
        case do
            staff <- List.find (\candidate -> unpackId candidate.id == entry.staffId) staffMembers
            payResult <- Map.lookup (timesheetEntryIdKey entry.id) payResults
            pure (staff, payResult)
        of
            Nothing -> []
            Just (staff, payResult) ->
                payResult.segments
                    |> filter (\segment -> segment.minutes > 0)
                    |> mapMaybe (segmentBucket weekStartsOn awardLevels baseRates penaltyRates timeAllowances staff payResult)

entryUsesImportedPayItem :: [StaffPayVersion] -> [ShiftTypePayVersion] -> TimesheetEntry -> Bool
entryUsesImportedPayItem staffPayVersions shiftTypePayVersions entry =
    maybe False staffVersionUsesImportedPayItem entry.staffPayVersionId
        || maybe False shiftVersionUsesImportedPayItem entry.shiftTypePayVersionId
    where
        staffVersionUsesImportedPayItem versionId =
            any (\version -> unpackId version.id == versionId && isJust version.importedXeroPayItemId) staffPayVersions
        shiftVersionUsesImportedPayItem versionId =
            any (\version -> unpackId version.id == versionId && isJust version.importedXeroPayItemId) shiftTypePayVersions

segmentBucket ::
    WeekdayIndex ->
    [AwardLevel] ->
    [AwardLevelBaseRate] ->
    [AwardLevelPenaltyRate] ->
    [AwardTimePenaltyAllowance] ->
    Staff ->
    TimesheetPayResult ->
    PaySegment ->
    Maybe XeroLocalEarningsBucket
segmentBucket weekStartsOn awardLevels baseRates penaltyRates timeAllowances staff payResult segment = do
    segmentDate <- segment.segmentDate
    payLevelId <- segment.payLevelId <|> payResult.payLevelId <|> fmap unpackId staff.defaultAwardLevelId
    awardLevel <- List.find (\level -> unpackId level.id == payLevelId) awardLevels
    let condition = fromMaybe "ordinary" segment.penaltyKind
    rawEffectiveFrom <-
        if condition == "ordinary"
            then ordinaryEffectiveFrom baseRates payLevelId staff.employmentBasis segmentDate
            else penaltyEffectiveFrom awardLevel baseRates penaltyRates timeAllowances payLevelId staff.employmentBasis condition segmentDate
    let effectiveFrom = venueEffectiveRateDate weekStartsOn <$> rawEffectiveFrom
        key =
            "xero:pay-item:classification:"
                <> tshow awardLevel.classificationFixedId
                <> ":basis:"
                <> inputValue staff.employmentBasis
                <> ":effective:"
                <> maybe "undated" tshow effectiveFrom
                <> ":"
                <> if condition == "ordinary" then "ordinary" else "penalty:" <> condition
    pure XeroLocalEarningsBucket {localBucketKey = key, localBucketLabel = key}

ordinaryEffectiveFrom :: [AwardLevelBaseRate] -> UUID -> StaffEmploymentBasisEnum -> Day -> Maybe (Maybe Day)
ordinaryEffectiveFrom baseRates payLevelId employmentBasis segmentDate =
    baseRates
        |> filter (\rate -> rate.awardLevelId == payLevelId && rate.employmentBasis == employmentBasis && activeOn segmentDate rate.operativeFrom rate.operativeTo)
        |> List.sortOn (.operativeFrom)
        |> listToMaybe
        |> fmap (.operativeFrom)

penaltyEffectiveFrom ::
    AwardLevel ->
    [AwardLevelBaseRate] ->
    [AwardLevelPenaltyRate] ->
    [AwardTimePenaltyAllowance] ->
    UUID ->
    StaffEmploymentBasisEnum ->
    Text ->
    Day ->
    Maybe (Maybe Day)
penaltyEffectiveFrom awardLevel baseRates penaltyRates timeAllowances payLevelId employmentBasis penaltyKindText segmentDate = do
    penaltyKind <- parsePenaltyKind penaltyKindText
    case delayedMealBreakSourcePenaltyKind penaltyKind of
        Just Nothing ->
            ordinaryEffectiveFrom baseRates payLevelId employmentBasis segmentDate
        Just (Just sourcePenaltyKind) ->
            activeLevelPenaltyEffectiveFrom penaltyRates payLevelId employmentBasis sourcePenaltyKind segmentDate
        Nothing ->
            activeLevelPenaltyEffectiveFrom penaltyRates payLevelId employmentBasis penaltyKind segmentDate
                <|> activeTimeAllowanceEffectiveFrom timeAllowances awardLevel.awardFixedId penaltyKind segmentDate

activeLevelPenaltyEffectiveFrom :: [AwardLevelPenaltyRate] -> UUID -> StaffEmploymentBasisEnum -> AwardPenaltyKindEnum -> Day -> Maybe (Maybe Day)
activeLevelPenaltyEffectiveFrom penaltyRates payLevelId employmentBasis penaltyKind segmentDate =
    penaltyRates
        |> filter (\rate -> rate.awardLevelId == payLevelId && rate.employmentBasis == employmentBasis && rate.penaltyKind == penaltyKind && activeOn segmentDate rate.operativeFrom rate.operativeTo)
        |> List.sortOn (.operativeFrom)
        |> listToMaybe
        |> fmap (.operativeFrom)

activeTimeAllowanceEffectiveFrom :: [AwardTimePenaltyAllowance] -> Int -> AwardPenaltyKindEnum -> Day -> Maybe (Maybe Day)
activeTimeAllowanceEffectiveFrom timeAllowances awardFixedId penaltyKind segmentDate =
    timeAllowances
        |> filter (\allowance -> allowance.awardFixedId == awardFixedId && allowance.penaltyKind == penaltyKind && activeOn segmentDate allowance.operativeFrom allowance.operativeTo)
        |> List.sortOn (.operativeFrom)
        |> listToMaybe
        |> fmap (.operativeFrom)

delayedMealBreakSourcePenaltyKind :: AwardPenaltyKindEnum -> Maybe (Maybe AwardPenaltyKindEnum)
delayedMealBreakSourcePenaltyKind DelayedMealBreakWeekday = Just Nothing
delayedMealBreakSourcePenaltyKind DelayedMealBreakSaturday = Just (Just SaturdayPenalty)
delayedMealBreakSourcePenaltyKind DelayedMealBreakSunday = Just (Just SundayPenalty)
delayedMealBreakSourcePenaltyKind DelayedMealBreakPublicHoliday = Just (Just PublicHolidayPenalty)
delayedMealBreakSourcePenaltyKind _ = Nothing

parsePenaltyKind :: Text -> Maybe AwardPenaltyKindEnum
parsePenaltyKind "evening_after_7pm" = Just EveningAfter7Pm
parsePenaltyKind "late_night_after_midnight" = Just LateNightAfterMidnight
parsePenaltyKind "saturday_penalty" = Just SaturdayPenalty
parsePenaltyKind "sunday_penalty" = Just SundayPenalty
parsePenaltyKind "public_holiday_penalty" = Just PublicHolidayPenalty
parsePenaltyKind "delayed_meal_break_weekday" = Just DelayedMealBreakWeekday
parsePenaltyKind "delayed_meal_break_saturday" = Just DelayedMealBreakSaturday
parsePenaltyKind "delayed_meal_break_sunday" = Just DelayedMealBreakSunday
parsePenaltyKind "delayed_meal_break_public_holiday" = Just DelayedMealBreakPublicHoliday
parsePenaltyKind _ = Nothing

activeOn :: Day -> Maybe Day -> Maybe Day -> Bool
activeOn day effectiveFrom effectiveTo =
    maybe True (<= day) effectiveFrom && maybe True (>= day) effectiveTo

dedupeBuckets :: [XeroLocalEarningsBucket] -> [XeroLocalEarningsBucket]
dedupeBuckets buckets =
    buckets
        |> List.sortOn (.localBucketKey)
        |> List.groupBy (\left right -> left.localBucketKey == right.localBucketKey)
        |> mapMaybe listToMaybe

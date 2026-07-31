module Application.Helper.Export.Payloads where

import Application.Helper.Export.Definitions
import Application.Helper.Export.ReadModel
import Application.Helper.Export.Render
import Application.Helper.Export.Types
import Application.Helper.Staff (isTrialStaff)
import Application.WageEngine
import Application.WagePublication
import Data.Coerce (coerce)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Generated.Types
import IHP.ControllerPrelude

buildFixedStaffPayCsvPayload ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Map.Map UUID WageCalculation ->
    ReportWeekSlice ->
    IO (Either Text StaffPayCsvPayload)
buildFixedStaffPayCsvPayload calculationsByEntryId reportWeekSlice = do
    entries <- fetchApprovedTimesheetEntries reportWeekSlice.sliceStart reportWeekSlice.sliceEnd
    staffById <- fetchReportStaffMap entries
    labelsByEntryId <- fetchApprovedEntryStaffHoursLabels entries
    versionManifestsByEntryId <- fetchVersionManifestsForEntries entries
    let reportWeekSelection = reportWeekSlice.weekSelection
        filteredEntries = filter (shouldIncludeFixedStaffPayEntry staffById) entries
    let missingCalculations = filter (\entry -> Map.notMember (unpackId entry.id) calculationsByEntryId) filteredEntries
    if not (null missingCalculations)
        then pure (Left "Failed to resolve sealed payroll data for one or more approved timesheet entries.")
        else do
            let records = buildFixedStaffPayCsvRecords reportWeekSelection filteredEntries staffById calculationsByEntryId labelsByEntryId
                versionManifests =
                    filteredEntries
                        |> mapMaybe (\entry -> Map.lookup (coerce (get #id entry)) versionManifestsByEntryId)
                        |> List.nub
                        |> List.sort
            if null records
                then pure (Left "No approved staff hours were found for the selected roster week.")
                else
                    pure $
                        Right
                            StaffPayCsvPayload
                                { weekSelection = reportWeekSelection
                                , fileName = "staff_hrs_starting-" <> tshow reportWeekSelection.weekStart <> ".csv"
                                , csvContents = renderStaffPayCsv reportWeekSelection records
                                , entryCount = length filteredEntries
                                , rowCount = length records
                                , versionManifests
                                , exportVersionManifest = collapseVersionManifests versionManifests
                                }

buildFixedStaffPayCsvRecords ::
    ReportWeekSelection ->
    [TimesheetEntry] ->
    Map.Map UUID Staff ->
    Map.Map UUID WageCalculation ->
    Map.Map UUID (Maybe Text) ->
    [StaffPayCsvRecord]
buildFixedStaffPayCsvRecords reportWeekSelection entries staffById calculationsByEntryId labelsByEntryId =
    aggregated
        |> Map.toList
        |> map toRecord
        |> List.sortOn (\record -> (Text.toCaseFold record.staffLastName, Text.toCaseFold record.staffFirstName, isJust record.label, Text.toCaseFold (fromMaybe "" record.label)))
  where
    buckets = staffPayBuckets reportWeekSelection
    emptyBucketHours = replicate (length buckets) 0
    aggregated = foldl' accumulateEntry Map.empty entries

    accumulateEntry acc entry =
        case (Map.lookup entry.staffId staffById, Map.lookup (unpackId entry.id) calculationsByEntryId) of
            (Just staff, Just calculation) ->
                foldl' (accumulateContribution staff (Map.findWithDefault Nothing (unpackId entry.id) labelsByEntryId)) acc (staffHoursContributions calculation)
            _ -> acc

    accumulateContribution staff payLabel acc contribution =
        case staffPayContributionBucketIndex buckets contribution of
            Nothing -> acc
            Just bucketIndex ->
                let key = (staff.lastName, staff.firstName, payLabel)
                 in Map.alter (Just . addDayHours bucketIndex contribution.staffHoursQuantity . fromMaybe emptyBucketHours) key acc

    toRecord ((lastName, firstName, payLabel), hoursByBucket) =
        StaffPayCsvRecord
            { staffFirstName = firstName
            , staffLastName = lastName
            , label = payLabel
            , bucketHours = map roundHourlyQuantity hoursByBucket
            }

shouldIncludeFixedStaffPayEntry :: Map.Map UUID Staff -> TimesheetEntry -> Bool
shouldIncludeFixedStaffPayEntry staffById entry =
    maybe False (\staff -> staff.isActive && isNothing staff.archivedAt && not (isTrialStaff staff)) (Map.lookup entry.staffId staffById)

weeklyFolderName :: ReportWeekSelection -> Text
weeklyFolderName reportWeekSelection =
    tshow reportWeekSelection.weekStart <> "-to-" <> tshow reportWeekSelection.weekEnd

collapseVersionManifests :: [Text] -> Maybe Text
collapseVersionManifests versionManifests =
    case List.nub versionManifests of
        []             -> Nothing
        [versionLabel] -> Just versionLabel
        _              -> Just "mixed"

data PayrollEarningsAggregation = PayrollEarningsAggregation
    { aggregationStaffFirstName      :: !Text
    , aggregationStaffLastName       :: !Text
    , aggregationWorkDate            :: !Day
    , aggregationPayLabels           :: ![Text]
    , aggregationTrackingCodes       :: ![Text]
    , aggregationComponents          :: ![EarningsComponent]
    , aggregationStaffId             :: !UUID
    , aggregationTimesheetEntryIds   :: ![UUID]
    , aggregationVersionManifests    :: ![Text]
    , aggregationCalculationVersions :: ![Text]
    , aggregationRateBookVersions    :: ![Text]
    , aggregationShiftTypeNames      :: ![Text]
    , aggregationApprovedAt          :: ![UTCTime]
    , aggregationApprovedByUserIds   :: ![UUID]
    , aggregationPayCalculationIds   :: ![UUID]
    }
    deriving (Eq, Show)

buildPayrollEarningsCsvRecords ::
    [TimesheetEntry] ->
    Map.Map UUID Staff ->
    Map.Map UUID WageCalculation ->
    Map.Map UUID (Maybe Text) ->
    Map.Map UUID Text ->
    Map.Map UUID Text ->
    [PayrollEarningsCsvRecord]
buildPayrollEarningsCsvRecords entries staffById calculationsByEntryId labelsByEntryId shiftLabelsByEntryId versionManifestsByEntryId =
    aggregated
        |> Map.elems
        |> concatMap toRecords
        |> List.sortOn (\record -> (record.workDate, Text.toCaseFold record.staffLastName, Text.toCaseFold record.staffFirstName, record.earningsRateName, record.unit, record.ratePerUnit))
  where
    aggregated = foldl' accumulateEntry Map.empty entries

    accumulateEntry acc entry =
        case (Map.lookup entry.staffId staffById, Map.lookup (unpackId entry.id) calculationsByEntryId) of
            (Just staff, Just calculation) ->
                foldl' (accumulateComponent entry staff calculation) acc (datedEarningsComponents calculation)
            _ -> acc

    accumulateComponent entry staff calculation acc (componentDate, component)
        | component.quantity <= 0 = acc
        | otherwise =
            let entryId = unpackId entry.id
                staffId = unpackId staff.id
                payLabel = Map.findWithDefault Nothing entryId labelsByEntryId
                trackingCode = Map.lookup entryId shiftLabelsByEntryId
                key = (staffId, componentDate, publicationBucketKey component)
                newAggregation =
                    PayrollEarningsAggregation
                        { aggregationStaffFirstName = staff.firstName
                        , aggregationStaffLastName = staff.lastName
                        , aggregationWorkDate = componentDate
                        , aggregationPayLabels = maybeToList payLabel
                        , aggregationTrackingCodes = maybeToList trackingCode
                        , aggregationComponents = [component]
                        , aggregationStaffId = staffId
                        , aggregationTimesheetEntryIds = [entryId]
                        , aggregationVersionManifests = maybeToList (Map.lookup entryId versionManifestsByEntryId)
                        , aggregationCalculationVersions = [let WageCalculationVersion value = calculation.calculationVersion in value]
                        , aggregationRateBookVersions = maybeToList (fmap (\(RateBookVersion value) -> value) calculation.calculationRateBookVersion)
                        , aggregationShiftTypeNames = maybeToList trackingCode
                        , aggregationApprovedAt = maybeToList entry.approvedAt
                        , aggregationApprovedByUserIds = maybeToList entry.approvedByUserId
                        , aggregationPayCalculationIds = maybeToList (unpackId <$> entry.activePayCalculationId)
                        }
             in Map.insertWith mergeAggregation key newAggregation acc

    mergeAggregation new old =
        old
            { aggregationPayLabels = sortNub (old.aggregationPayLabels <> new.aggregationPayLabels)
            , aggregationTrackingCodes = sortNub (old.aggregationTrackingCodes <> new.aggregationTrackingCodes)
            , aggregationComponents = old.aggregationComponents <> new.aggregationComponents
            , aggregationTimesheetEntryIds = sortNub (old.aggregationTimesheetEntryIds <> new.aggregationTimesheetEntryIds)
            , aggregationVersionManifests = sortNub (old.aggregationVersionManifests <> new.aggregationVersionManifests)
            , aggregationCalculationVersions = sortNub (old.aggregationCalculationVersions <> new.aggregationCalculationVersions)
            , aggregationRateBookVersions = sortNub (old.aggregationRateBookVersions <> new.aggregationRateBookVersions)
            , aggregationShiftTypeNames = sortNub (old.aggregationShiftTypeNames <> new.aggregationShiftTypeNames)
            , aggregationApprovedAt = sortNub (old.aggregationApprovedAt <> new.aggregationApprovedAt)
            , aggregationApprovedByUserIds = sortNub (old.aggregationApprovedByUserIds <> new.aggregationApprovedByUserIds)
            , aggregationPayCalculationIds = sortNub (old.aggregationPayCalculationIds <> new.aggregationPayCalculationIds)
            }

    toRecords aggregation =
        [ let bucket = line.publishedBucketKey
              sourceConditionText = sourceConditionValue bucket.finalEarningsBucketSourceCondition
              payLabel = collapseOptionalText aggregation.aggregationPayLabels
              trackingCode = collapseOptionalText aggregation.aggregationTrackingCodes
           in PayrollEarningsCsvRecord
                { staffFirstName = aggregation.aggregationStaffFirstName
                , staffLastName = aggregation.aggregationStaffLastName
                , workDate = aggregation.aggregationWorkDate
                , earningsRateName = earningsLineName payLabel bucket.finalEarningsBucketSourceCondition
                , exactQuantity = line.publishedExactQuantity
                , quantity = line.publishedQuantity
                , unit = earningsUnitText bucket.finalEarningsBucketUnitType
                , ratePerUnit = toRational bucket.finalEarningsBucketRatePerUnit
                , exactAmount = line.publishedExactAmount
                , amount = line.publishedAmount
                , trackingCode
                , description = "Bepis entries: " <> Text.intercalate " " (map tshow aggregation.aggregationTimesheetEntryIds)
                , staffId = aggregation.aggregationStaffId
                , timesheetEntryIds = aggregation.aggregationTimesheetEntryIds
                , payConfigVersionManifest = collapseVersionManifests aggregation.aggregationVersionManifests
                , calculationSource = calculationSourceValue bucket.finalEarningsBucketCalculationSource
                , calculationVersion = collapseText aggregation.aggregationCalculationVersions
                , rateBookVersion = collapseOptionalText aggregation.aggregationRateBookVersions
                , sourceCondition = sourceConditionText
                , sourceRateIdentity = fmap (\(RateSourceIdentity value) -> value) bucket.finalEarningsBucketSourceRateIdentity
                , sourcePayLevelName = payLabel
                , sourceShiftTypeName = collapseOptionalText aggregation.aggregationShiftTypeNames
                , approvedAt = aggregation.aggregationApprovedAt
                , approvedByUserIds = aggregation.aggregationApprovedByUserIds
                , activePayCalculationIds = aggregation.aggregationPayCalculationIds
                }
        | line <- derivePublishedEarnings aggregation.aggregationComponents
        ]

calculationMap :: [TimesheetEntry] -> [WageCalculation] -> Map.Map UUID WageCalculation
calculationMap entries calculations =
    Map.fromList (zip (map (unpackId . (.id)) entries) calculations)

earningsLineName :: Maybe Text -> SourceCondition -> Text
earningsLineName payLabel condition =
    fromMaybe "Unlabelled" payLabel <> " - " <> conditionLabel condition

conditionLabel :: SourceCondition -> Text
conditionLabel = \case
    OrdinaryCondition                -> "Ordinary"
    SaturdayCondition                -> "Saturday"
    SundayCondition                  -> "Sunday"
    PublicHolidayCondition           -> "Public Holiday"
    EveningAdditionCondition         -> "Evening After 7pm Addition"
    EarlyMorningAdditionCondition    -> "Early Morning Addition"
    MissedMealBreakAdditionCondition -> "Missed Meal Break 50% Addition"
    ImportedFlatRateCondition _      -> "Imported Xero Rate"

earningsUnitText :: EarningsUnit -> Text
earningsUnitText Hours          = "hours"
earningsUnitText CommencedHours = "commenced_hours"

collapseText :: [Text] -> Text
collapseText values = fromMaybe "" (collapseOptionalText values)

collapseOptionalText :: [Text] -> Maybe Text
collapseOptionalText values =
    case List.nub values of
        []      -> Nothing
        [value] -> Just value
        _       -> Just "mixed"

sortNub :: Ord value => [value] -> [value]
sortNub = List.sort . List.nub

buildApprovedTimesheetExportFileName :: Day -> Day -> Text
buildApprovedTimesheetExportFileName rangeStart rangeEnd =
    "approved-timesheets-" <> tshow rangeStart <> "-to-" <> tshow rangeEnd <> ".csv"

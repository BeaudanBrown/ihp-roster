module Application.Helper.Export.Payloads where

import Application.Helper.Export.Definitions
import Application.Helper.Export.ReadModel
import Application.Helper.Export.Render
import Application.Helper.Export.Types
import Application.Helper.Pay (PaySegment (..), TimesheetPayResult (..),
                               fetchTimesheetPayResultsForEntries,
                               timesheetEntryIdKey)
import Application.Helper.Staff (isTrialStaff)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Generated.Types
import IHP.ControllerPrelude

buildStaffPayCsvPayload ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    VenueReportDefinition ->
    Int ->
    IO (Either Text StaffPayCsvPayload)
buildStaffPayCsvPayload reportDefinition selectedWeekOffset = do
    reportWeekSelection <- fetchReportWeekSelection selectedWeekOffset
    entries <- fetchApprovedTimesheetEntries reportWeekSelection.weekStart reportWeekSelection.weekEnd
    staffById <- fetchReportStaffMap entries
    payResultsByEntryId <- fetchTimesheetPayResultsForEntries entries
    versionManifestsByEntryId <- fetchVersionManifestsForEntries entries
    let filteredEntries = filter (shouldIncludeStaffPayEntry reportDefinition staffById) entries
    let missingEntryIds =
            map (tshow . get #id) $
                filter (\entry -> Map.notMember (timesheetEntryIdKey (get #id entry)) payResultsByEntryId) filteredEntries

    if not (null missingEntryIds)
        then pure (Left "Failed to resolve payroll data for one or more approved timesheet entries.")
        else do
            let records = buildStaffPayCsvRecords reportDefinition reportWeekSelection filteredEntries staffById payResultsByEntryId
            let exportVersionManifests =
                    filteredEntries
                        |> mapMaybe (\entry -> Map.lookup (coerce (get #id entry)) versionManifestsByEntryId)
                        |> List.nub
                        |> List.sort
            let exportVersionManifest = collapseVersionManifests exportVersionManifests
            pure $
                Right
                    StaffPayCsvPayload
                        { weekSelection = reportWeekSelection
                        , fileName = reportDefinition.definition.slug <> "-" <> tshow reportWeekSelection.weekStart <> ".csv"
                        , csvContents = renderStaffPayCsv reportWeekSelection records
                        , entryCount = length filteredEntries
                        , rowCount = length records
                        , versionManifests = exportVersionManifests
                        , exportVersionManifest
                        }

buildStaffPayCsvScope :: VenueReportDefinition -> StaffPayCsvPayload -> Aeson.Value
buildStaffPayCsvScope reportDefinition payload =
    Aeson.object
        [ "reportDefinitionId" Aeson..= unpackId (get #id reportDefinition.definition)
        , "reportSlug" Aeson..= reportDefinition.definition.slug
        , "reportName" Aeson..= reportDefinition.definition.name
        , "reportEngine" Aeson..= reportDefinitionEngineToText reportDefinition.engine
        , "weekOffset" Aeson..= payload.weekSelection.weekOffset
        , "weekStart" Aeson..= payload.weekSelection.weekStart
        , "weekEnd" Aeson..= payload.weekSelection.weekEnd
        , "dayLabels" Aeson..= payload.weekSelection.dayLabels
        , "entryCount" Aeson..= payload.entryCount
        , "rowCount" Aeson..= payload.rowCount
        , "versionManifests" Aeson..= payload.versionManifests
        , "filterShiftTypes" Aeson..= map (.name) reportDefinition.shiftTypeFilters
        ]

buildPayrollEarningsCsvPayload ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    VenueReportDefinition ->
    Int ->
    IO (Either Text PayrollEarningsCsvPayload)
buildPayrollEarningsCsvPayload reportDefinition selectedWeekOffset = do
    reportWeekSelection <- fetchReportWeekSelection selectedWeekOffset
    entries <- fetchApprovedTimesheetEntries reportWeekSelection.weekStart reportWeekSelection.weekEnd
    staffById <- fetchReportStaffMap entries
    payResultsByEntryId <- fetchTimesheetPayResultsForEntries entries
    versionManifestsByEntryId <- fetchVersionManifestsForEntries entries
    let filteredEntries = filter (shouldIncludeStaffPayEntry reportDefinition staffById) entries
    let missingEntryIds =
            map (tshow . get #id) $
                filter (\entry -> Map.notMember (timesheetEntryIdKey (get #id entry)) payResultsByEntryId) filteredEntries

    if not (null missingEntryIds)
        then pure (Left "Failed to resolve payroll data for one or more approved timesheet entries.")
        else do
            let records = buildPayrollEarningsCsvRecords filteredEntries staffById payResultsByEntryId versionManifestsByEntryId
            let exportVersionManifests =
                    filteredEntries
                        |> mapMaybe (\entry -> Map.lookup (coerce (get #id entry)) versionManifestsByEntryId)
                        |> List.nub
                        |> List.sort
            let exportVersionManifest = collapseVersionManifests exportVersionManifests
            pure $
                Right
                    PayrollEarningsCsvPayload
                        { weekSelection = reportWeekSelection
                        , fileName = reportDefinition.definition.slug <> "-" <> tshow reportWeekSelection.weekStart <> ".csv"
                        , csvContents = renderPayrollEarningsCsv records
                        , entryCount = length filteredEntries
                        , rowCount = length records
                        , versionManifests = exportVersionManifests
                        , exportVersionManifest
                        }

buildPayrollEarningsCsvScope :: VenueReportDefinition -> PayrollEarningsCsvPayload -> Aeson.Value
buildPayrollEarningsCsvScope reportDefinition payload =
    Aeson.object
        [ "reportDefinitionId" Aeson..= unpackId (get #id reportDefinition.definition)
        , "reportSlug" Aeson..= reportDefinition.definition.slug
        , "reportName" Aeson..= reportDefinition.definition.name
        , "reportEngine" Aeson..= reportDefinitionEngineToText reportDefinition.engine
        , "weekOffset" Aeson..= payload.weekSelection.weekOffset
        , "weekStart" Aeson..= payload.weekSelection.weekStart
        , "weekEnd" Aeson..= payload.weekSelection.weekEnd
        , "dayLabels" Aeson..= payload.weekSelection.dayLabels
        , "entryCount" Aeson..= payload.entryCount
        , "rowCount" Aeson..= payload.rowCount
        , "versionManifests" Aeson..= payload.versionManifests
        , "filterShiftTypes" Aeson..= map (.name) reportDefinition.shiftTypeFilters
        ]

buildHourlyBreakdownZipPayload ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    VenueReportDefinition ->
    Int ->
    IO (Either Text HourlyBreakdownZipPayload)
buildHourlyBreakdownZipPayload reportDefinition selectedWeekOffset = do
    reportWeekSelection <- fetchReportWeekSelection selectedWeekOffset
    entries <- fetchApprovedTimesheetEntries reportWeekSelection.weekStart reportWeekSelection.weekEnd
    let filteredEntries = filter (shouldIncludeHourlyBreakdownEntry reportDefinition) entries
    versionManifestsByEntryId <- fetchVersionManifestsForEntries filteredEntries
    shiftTypes <- fetchCurrentVenueReportShiftTypes reportDefinition
    let versionManifests =
            filteredEntries
                |> mapMaybe (\entry -> Map.lookup (coerce (get #id entry)) versionManifestsByEntryId)
                |> List.nub
                |> List.sort
    let exportVersionManifest = collapseVersionManifests versionManifests
    let zipContentsBase64 = renderHourlyBreakdownZipBase64 reportWeekSelection shiftTypes filteredEntries
    pure $
        Right
            HourlyBreakdownZipPayload
                { weekSelection = reportWeekSelection
                , fileName = reportDefinition.definition.slug <> "-" <> tshow reportWeekSelection.weekStart <> ".zip"
                , zipContentsBase64
                , entryCount = length filteredEntries
                , fileCount = length reportWeekSelection.dayLabels
                , versionManifests
                , exportVersionManifest
                }

buildHourlyBreakdownZipScope :: VenueReportDefinition -> HourlyBreakdownZipPayload -> Aeson.Value
buildHourlyBreakdownZipScope reportDefinition payload =
    Aeson.object
        [ "reportDefinitionId" Aeson..= unpackId (get #id reportDefinition.definition)
        , "reportSlug" Aeson..= reportDefinition.definition.slug
        , "reportName" Aeson..= reportDefinition.definition.name
        , "reportEngine" Aeson..= reportDefinitionEngineToText reportDefinition.engine
        , "weekOffset" Aeson..= payload.weekSelection.weekOffset
        , "weekStart" Aeson..= payload.weekSelection.weekStart
        , "weekEnd" Aeson..= payload.weekSelection.weekEnd
        , "dayLabels" Aeson..= payload.weekSelection.dayLabels
        , "entryCount" Aeson..= payload.entryCount
        , "fileCount" Aeson..= payload.fileCount
        , "versionManifests" Aeson..= payload.versionManifests
        , "filterShiftTypes" Aeson..= map (.name) reportDefinition.shiftTypeFilters
        ]

buildFixedStaffPayCsvPayload ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    ReportWeekSlice ->
    IO (Either Text StaffPayCsvPayload)
buildFixedStaffPayCsvPayload reportWeekSlice = do
    entries <- fetchApprovedTimesheetEntries reportWeekSlice.sliceStart reportWeekSlice.sliceEnd
    staffById <- fetchReportStaffMap entries
    payResultsByEntryId <- fetchTimesheetPayResultsForEntries entries
    versionManifestsByEntryId <- fetchVersionManifestsForEntries entries
    let reportWeekSelection = reportWeekSlice.weekSelection
    let filteredEntries = filter (shouldIncludeFixedStaffPayEntry staffById) entries
    let missingEntryIds =
            map (tshow . get #id) $
                filter (\entry -> Map.notMember (timesheetEntryIdKey (get #id entry)) payResultsByEntryId) filteredEntries

    if not (null missingEntryIds)
        then pure (Left "Failed to resolve payroll data for one or more approved timesheet entries.")
        else do
            let records = buildFixedStaffPayCsvRecords reportWeekSelection filteredEntries staffById payResultsByEntryId
            let versionManifests =
                    filteredEntries
                        |> mapMaybe (\entry -> Map.lookup (coerce (get #id entry)) versionManifestsByEntryId)
                        |> List.nub
                        |> List.sort
            pure $
                Right
                    StaffPayCsvPayload
                        { weekSelection = reportWeekSelection
                        , fileName = "staff_hours-" <> tshow reportWeekSelection.weekStart <> ".csv"
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
    Map.Map Text TimesheetPayResult ->
    [StaffPayCsvRecord]
buildFixedStaffPayCsvRecords reportWeekSelection entries staffById payResultsByEntryId =
    aggregated
        |> Map.toList
        |> map toRecord
        |> List.sortOn (\record -> (record.staffName, record.label))
    where
        aggregated =
            foldl' accumulate Map.empty entries

        accumulate acc entry =
            case (Map.lookup entry.staffId staffById, Map.lookup (timesheetEntryIdKey (get #id entry)) payResultsByEntryId) of
                (Just staff, Just payResult) ->
                    foldl' (accumulateSegment staff payResult) acc payResult.segments
                _ -> acc

        buckets = staffPayBuckets reportWeekSelection

        emptyBucketHours = replicate (length buckets) 0

        accumulateSegment staff payResult acc segment =
            case staffPaySegmentBucketIndex buckets segment of
                Just bucketIndex ->
                    let key = (staffPayDisplayName staff, fixedStaffPayRecordLabel payResult)
                        hours = paidMinutesToHours segment.minutes
                     in if hours <= 0
                            then acc
                            else Map.alter (Just . addDayHours bucketIndex hours . fromMaybe emptyBucketHours) key acc
                Nothing -> acc

        toRecord ((recordStaffName, recordLabel), recordBucketHours) =
            StaffPayCsvRecord
                { staffName = recordStaffName
                , label = recordLabel
                , bucketHours = recordBucketHours
                , total = sum recordBucketHours
                }

shouldIncludeFixedStaffPayEntry :: Map.Map UUID Staff -> TimesheetEntry -> Bool
shouldIncludeFixedStaffPayEntry staffById entry =
    case Map.lookup entry.staffId staffById of
        Nothing    -> False
        Just staff -> not (isTrialStaff staff)

weeklyFolderName :: ReportWeekSelection -> Text
weeklyFolderName reportWeekSelection =
    tshow reportWeekSelection.weekStart <> "-to-" <> tshow reportWeekSelection.weekEnd

collapseVersionManifests :: [Text] -> Maybe Text
collapseVersionManifests versionManifests =
    case List.nub versionManifests of
        []             -> Nothing
        [versionLabel] -> Just versionLabel
        _              -> Just "mixed"

shouldIncludeStaffPayEntry :: VenueReportDefinition -> Map.Map UUID Staff -> TimesheetEntry -> Bool
shouldIncludeStaffPayEntry reportDefinition staffById entry =
    case Map.lookup entry.staffId staffById of
        Nothing -> False
        Just staff ->
            not (isTrialStaff staff)
                && (null allowedShiftTypeIds || entry.shiftTypeId `elem` allowedShiftTypeIds)
    where
        allowedShiftTypeIds = map (coerce . get #id) reportDefinition.shiftTypeFilters

shouldIncludeHourlyBreakdownEntry :: VenueReportDefinition -> TimesheetEntry -> Bool
shouldIncludeHourlyBreakdownEntry reportDefinition entry =
    null allowedShiftTypeIds || entry.shiftTypeId `elem` allowedShiftTypeIds
    where
        allowedShiftTypeIds = map (coerce . get #id) reportDefinition.shiftTypeFilters

buildStaffPayCsvRecords ::
    VenueReportDefinition ->
    ReportWeekSelection ->
    [TimesheetEntry] ->
    Map.Map UUID Staff ->
    Map.Map Text TimesheetPayResult ->
    [StaffPayCsvRecord]
buildStaffPayCsvRecords reportDefinition reportWeekSelection entries staffById payResultsByEntryId =
    aggregated
        |> Map.toList
        |> map toRecord
        |> List.sortOn (\record -> (record.staffName, record.label))
    where
        aggregated =
            foldl' accumulate Map.empty entries

        accumulate acc entry =
            case (Map.lookup entry.staffId staffById, Map.lookup (timesheetEntryIdKey (get #id entry)) payResultsByEntryId) of
                (Just staff, Just payResult) ->
                    foldl' (accumulateSegment staff payResult) acc payResult.segments
                _ -> acc

        buckets = staffPayBuckets reportWeekSelection

        emptyBucketHours = replicate (length buckets) 0

        accumulateSegment staff payResult acc segment =
            case staffPaySegmentBucketIndex buckets segment of
                Just bucketIndex ->
                    let key = (staffPayDisplayName staff, staffPayRecordLabel reportDefinition payResult)
                        hours = paidMinutesToHours segment.minutes
                     in if hours <= 0
                            then acc
                            else Map.alter (Just . addDayHours bucketIndex hours . fromMaybe emptyBucketHours) key acc
                Nothing -> acc

        toRecord ((recordStaffName, recordLabel), recordBucketHours) =
            StaffPayCsvRecord
                { staffName = recordStaffName
                , label = recordLabel
                , bucketHours = recordBucketHours
                , total = sum recordBucketHours
                }

data PayrollEarningsAggregation = PayrollEarningsAggregation
    { aggregationStaffFirstName      :: !Text
    , aggregationStaffLastName       :: !Text
    , aggregationWorkDate            :: !Day
    , aggregationEarningsRateName    :: !Text
    , aggregationTrackingCode        :: !(Maybe Text)
    , aggregationMinutes             :: !Int
    , aggregationStaffId             :: !UUID
    , aggregationTimesheetEntryIds   :: ![UUID]
    , aggregationVersionManifests    :: ![Text]
    , aggregationSourcePenaltyKind   :: !Text
    , aggregationSourcePayLevelName  :: !(Maybe Text)
    , aggregationSourceShiftTypeName :: !(Maybe Text)
    }
    deriving (Eq, Show)

buildPayrollEarningsCsvRecords ::
    [TimesheetEntry] ->
    Map.Map UUID Staff ->
    Map.Map Text TimesheetPayResult ->
    Map.Map UUID Text ->
    [PayrollEarningsCsvRecord]
buildPayrollEarningsCsvRecords entries staffById payResultsByEntryId versionManifestsByEntryId =
    aggregated
        |> Map.elems
        |> map toRecord
        |> List.sortOn (\record -> (record.workDate, record.staffLastName, record.staffFirstName, record.earningsRateName, record.trackingCode))
    where
        aggregated =
            foldl' accumulate Map.empty entries

        accumulate acc entry =
            case (Map.lookup entry.staffId staffById, Map.lookup (timesheetEntryIdKey (get #id entry)) payResultsByEntryId) of
                (Just staff, Just payResult) ->
                    foldl' (accumulateSegment entry staff payResult) acc payResult.segments
                _ -> acc

        accumulateSegment entry staff payResult acc segment =
            case segment.segmentDate of
                Nothing -> acc
                Just segmentDate
                    | segment.minutes <= 0 -> acc
                    | otherwise ->
                        let staffId = coerce (get #id staff)
                            entryId = coerce (get #id entry)
                            trackingCode = segment.shiftTypeName <|> payResult.shiftTypeName
                            earningsRateName = payrollEarningsRateName payResult segment
                            sourcePenaltyKind = payrollEarningsPenaltyKind segment
                            sourcePayLevelName = segment.payLevelName <|> payResult.payLevelName
                            sourceShiftTypeName = segment.shiftTypeName <|> payResult.shiftTypeName
                            versionManifests = maybeToList (Map.lookup (coerce (get #id entry)) versionManifestsByEntryId)
                            key = (staffId, segmentDate, earningsRateName, trackingCode)
                            newAggregation =
                                PayrollEarningsAggregation
                                    { aggregationStaffFirstName = staff.firstName
                                    , aggregationStaffLastName = staff.lastName
                                    , aggregationWorkDate = segmentDate
                                    , aggregationEarningsRateName = earningsRateName
                                    , aggregationTrackingCode = trackingCode
                                    , aggregationMinutes = segment.minutes
                                    , aggregationStaffId = staffId
                                    , aggregationTimesheetEntryIds = [entryId]
                                    , aggregationVersionManifests = versionManifests
                                    , aggregationSourcePenaltyKind = sourcePenaltyKind
                                    , aggregationSourcePayLevelName = sourcePayLevelName
                                    , aggregationSourceShiftTypeName = sourceShiftTypeName
                                    }
                         in Map.insertWith mergeAggregation key newAggregation acc

        mergeAggregation new old =
            old
                { aggregationMinutes = old.aggregationMinutes + new.aggregationMinutes
                , aggregationTimesheetEntryIds = List.sort (List.nub (old.aggregationTimesheetEntryIds <> new.aggregationTimesheetEntryIds))
                , aggregationVersionManifests = List.sort (List.nub (old.aggregationVersionManifests <> new.aggregationVersionManifests))
                }

        toRecord aggregation =
            PayrollEarningsCsvRecord
                { staffFirstName = aggregation.aggregationStaffFirstName
                , staffLastName = aggregation.aggregationStaffLastName
                , workDate = aggregation.aggregationWorkDate
                , earningsRateName = aggregation.aggregationEarningsRateName
                , hours = paidMinutesToHours aggregation.aggregationMinutes
                , trackingCode = aggregation.aggregationTrackingCode
                , description = "Bepis entries: " <> Text.intercalate " " (map tshow aggregation.aggregationTimesheetEntryIds)
                , staffId = aggregation.aggregationStaffId
                , timesheetEntryIds = aggregation.aggregationTimesheetEntryIds
                , payConfigVersionManifest = versionManifestForAggregation aggregation.aggregationVersionManifests
                , sourcePenaltyKind = aggregation.aggregationSourcePenaltyKind
                , sourcePayLevelName = aggregation.aggregationSourcePayLevelName
                , sourceShiftTypeName = aggregation.aggregationSourceShiftTypeName
                }

        versionManifestForAggregation versionManifests =
            case List.nub versionManifests of
                []                -> Nothing
                [snapshotVersion] -> Just snapshotVersion
                _                 -> Just "mixed"

payrollEarningsRateName :: TimesheetPayResult -> PaySegment -> Text
payrollEarningsRateName payResult segment =
    payrollEarningsBaseName payResult segment <> " - " <> payrollEarningsPenaltyLabel segment

payrollEarningsBaseName :: TimesheetPayResult -> PaySegment -> Text
payrollEarningsBaseName payResult segment =
    fromMaybe "Unknown pay level" (segment.payLevelName <|> payResult.payLevelName)

payrollEarningsPenaltyKind :: PaySegment -> Text
payrollEarningsPenaltyKind segment =
    fromMaybe "ordinary" segment.penaltyKind

payrollEarningsPenaltyLabel :: PaySegment -> Text
payrollEarningsPenaltyLabel segment =
    case payrollEarningsPenaltyKind segment of
        "saturday_penalty"          -> "Saturday"
        "sunday_penalty"            -> "Sunday"
        "public_holiday_penalty"    -> "Public Holiday"
        "evening_after_7pm"         -> "Evening After 7pm"
        "late_night_after_midnight" -> "Late Night After Midnight"
        "delayed_meal_break_weekday" -> "M-F Delayed Meal Break"
        "delayed_meal_break_saturday" -> "Saturday Delayed Meal Break"
        "delayed_meal_break_sunday" -> "Sunday Delayed Meal Break"
        "delayed_meal_break_public_holiday" -> "Public Holiday Delayed Meal Break"
        _                           -> "Ordinary"

buildApprovedTimesheetExportFileName :: Day -> Day -> Text
buildApprovedTimesheetExportFileName rangeStart rangeEnd =
    "approved-timesheets-" <> tshow rangeStart <> "-to-" <> tshow rangeEnd <> ".csv"

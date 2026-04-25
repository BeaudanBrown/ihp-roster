module Application.Helper.Export
    ( module Application.Helper.Export
    , module Application.Helper.Export.Types
    , module Application.Helper.Export.Render
    ) where

import Application.Helper.Controller
import Application.Helper.Export.Render
import Application.Helper.Export.Types
import Application.Helper.Pay (PaySegment (..), PayTotals (..), TimesheetPayResult (..),
                               ensureCurrentVenuePayConfigSnapshot,
                               fetchTimesheetPayResultsForEntries,
                               timesheetEntryIdKey)
import Application.Helper.View (isTrialStaff)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Data.Time.Clock (NominalDiffTime, UTCTime, addUTCTime, getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude

currentReportWeekOffset ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO Int
currentReportWeekOffset = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    pure (venueWeekOffsetForDay venueConfig today)

fetchReportWeekSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Int ->
    IO ReportWeekSelection
fetchReportWeekSelection selectedWeekOffset = do
    venueConfig <- fetchVenueConfig
    let reportWeekStart = venueWeekStartDate venueConfig selectedWeekOffset
    let labels = fallbackReportDayLabels reportWeekStart
    let reportWeekEnd = addDays 6 reportWeekStart
    pure
        ReportWeekSelection
            { weekOffset = selectedWeekOffset
            , weekStart = reportWeekStart
            , weekEnd = reportWeekEnd
            , dayLabels = labels
            }

reportDefinitionEngineImplemented :: ReportDefinitionEngine -> Bool
reportDefinitionEngineImplemented StaffPayCsvReport        = True
reportDefinitionEngineImplemented HourlyBreakdownZipReport = True
reportDefinitionEngineImplemented PayrollEarningsCsvReport = True

requestReportDefinitionExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Text ->
    Int ->
    IO (Either Text ExportJob)
requestReportDefinitionExport reportSlug selectedWeekOffset = do
    reportDefinitions <- fetchCurrentVenueReportDefinitions
    case List.find (\reportDefinition -> reportDefinition.definition.slug == reportSlug) reportDefinitions of
        Nothing ->
            pure (Left "Report definition not found for the current venue.")
        Just reportDefinition ->
            case reportDefinition.engine of
                StaffPayCsvReport -> requestStaffPayCsvExport reportDefinition selectedWeekOffset
                HourlyBreakdownZipReport -> requestHourlyBreakdownZipExport reportDefinition selectedWeekOffset
                PayrollEarningsCsvReport -> requestPayrollEarningsCsvExport reportDefinition selectedWeekOffset

fetchCurrentVenueReportDefinitions ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO [VenueReportDefinition]
fetchCurrentVenueReportDefinitions = do
    definitions <- fetchCurrentVenueReportDefinitionsIncludingInactive
    pure (filter (.definition.isActive) definitions)

fetchCurrentVenueReportDefinitionsIncludingInactive ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO [VenueReportDefinition]
fetchCurrentVenueReportDefinitionsIncludingInactive = do
    bootstrapCurrentVenueReportDefinitionsIfMissing
    definitions <- query @ReportDefinition
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch
    filtersByDefinitionId <- fetchReportDefinitionShiftTypeFilters definitions
    pure (map (toVenueReportDefinition filtersByDefinitionId) definitions)

bootstrapCurrentVenueReportDefinitionsIfMissing ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO ()
bootstrapCurrentVenueReportDefinitionsIfMissing = do
    existingDefinitions <- query @ReportDefinition
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchCount
    when (existingDefinitions == 0) do
        shiftTypes <- query @ShiftType
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#isActive, True)
            |> orderByAsc #createdAt
            |> fetch
        void $ withTransaction do
            wageDefinition <- createReportDefinition "wage" "Wage Report" (Just "Hourly staff count breakdown per day (ZIP of CSVs)") HourlyBreakdownZipReport 10
            _ <- wageDefinition `seq` pure ()
            staffHoursDefinition <- createReportDefinition "staff_hours" "Staff Hours Report" (Just "Staff hours broken down by pay level and day") StaffPayCsvReport 20
            _ <- staffHoursDefinition `seq` pure ()
            payrollEarningsDefinition <- createReportDefinition "payroll_earnings" "Payroll Earnings CSV" (Just "Approved payroll earnings by staff, date, earnings bucket, and tracking code") PayrollEarningsCsvReport 25
            _ <- payrollEarningsDefinition `seq` pure ()
            forM_ (find (\shiftType -> shiftType.name == "Kitchen") shiftTypes) \kitchenShiftType -> do
                kitchenDefinition <- createReportDefinition "kitchen" "Kitchen Report" (Just "Kitchen staff hours by day") StaffPayCsvReport 30
                newRecord @ReportDefinitionShiftTypeFilter
                    |> set #reportDefinitionId (unpackId (get #id kitchenDefinition))
                    |> set #shiftTypeId (unpackId (get #id kitchenShiftType))
                    |> createRecord
            pure ()
    where
        createReportDefinition slug name description engine sortOrder =
            newRecord @ReportDefinition
                |> set #venueId (unpackId currentVenueId)
                |> set #slug slug
                |> set #name name
                |> set #description description
                |> set #engine (reportDefinitionEngineToText engine)
                |> set #sortOrder sortOrder
                |> createRecord

fetchReportDefinitionShiftTypeFilters ::
    (?modelContext :: ModelContext) =>
    [ReportDefinition] ->
    IO (Map.Map UUID [ShiftType])
fetchReportDefinitionShiftTypeFilters definitions =
    if null definitions
        then pure Map.empty
        else do
            filters <- query @ReportDefinitionShiftTypeFilter
                |> filterWhereIn (#reportDefinitionId, map (coerce . get #id) definitions)
                |> fetch
            let shiftTypeIds = List.nub (map (.shiftTypeId) filters)
            shiftTypes <-
                if null shiftTypeIds
                    then pure []
                    else query @ShiftType |> filterWhereIn (#id, map Id shiftTypeIds) |> fetch
            let shiftTypesById = Map.fromList (map (\shiftType -> (coerce (get #id shiftType), shiftType)) shiftTypes)
            pure $
                foldl'
                    (\acc filterRow ->
                        case Map.lookup filterRow.shiftTypeId shiftTypesById of
                            Just shiftType ->
                                Map.insertWith (<>) filterRow.reportDefinitionId [shiftType] acc
                            Nothing -> acc
                    )
                    Map.empty
                    filters

toVenueReportDefinition :: Map.Map UUID [ShiftType] -> ReportDefinition -> VenueReportDefinition
toVenueReportDefinition filtersByDefinitionId definition =
    VenueReportDefinition
        { definition
        , engine = fromMaybe StaffPayCsvReport (parseReportDefinitionEngine definition.engine)
        , shiftTypeFilters = fromMaybe [] (Map.lookup (coerce (get #id definition)) filtersByDefinitionId)
        }

requestStaffPayCsvExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    VenueReportDefinition ->
    Int ->
    IO (Either Text ExportJob)
requestStaffPayCsvExport reportDefinition selectedWeekOffset = do
    payloadResult <- buildStaffPayCsvPayload reportDefinition selectedWeekOffset
    case payloadResult of
        Left err -> pure (Left err)
        Right payload -> do
            exportJob <- withTransaction do
                now <- getCurrentTime
                let expiresAt = addUTCTime exportExpirySeconds now
                let exportType = exportJobTypeToText StaffPayCsv
                let initialScope = buildStaffPayCsvScope reportDefinition payload
                exportJob <-
                    newRecord @ExportJob
                        |> set #venueId (unpackId currentVenueId)
                        |> set #requestedByUserId (unpackId (get #id authenticatedCurrentUser))
                        |> set #exportType exportType
                        |> set #status (exportJobStatusToText ExportPending)
                        |> set #schemaVersion exportSchemaVersion
                        |> set #rangeStart (Just payload.weekSelection.weekStart)
                        |> set #rangeEnd (Just payload.weekSelection.weekEnd)
                        |> set #scope initialScope
                        |> set #deliveryMethod browserDownloadMethod
                        |> set #destinationMetadata (Aeson.object ["requestedVia" Aeson..= requestAuditSourceChannel])
                        |> set #expiresAt expiresAt
                        |> createRecord

                exportJob <-
                    exportJob
                        |> set #status (exportJobStatusToText ExportReady)
                        |> set #payConfigSnapshotVersion payload.exportSnapshotVersion
                        |> set #scope initialScope
                        |> set #fileName (Just payload.fileName)
                        |> set #contentType (Just "text/csv; charset=utf-8")
                        |> set #fileEncoding "utf8"
                        |> set #fileContents (Just payload.csvContents)
                        |> updateRecord

                void $ recordCurrentUserAuditEvent
                    "export_generated"
                    "export_jobs"
                    (unpackId (get #id exportJob))
                    (Aeson.object
                        [ "exportType" Aeson..= exportType
                        , "reportSlug" Aeson..= reportDefinition.definition.slug
                        , "reportEngine" Aeson..= reportDefinitionEngineToText reportDefinition.engine
                        , "weekOffset" Aeson..= payload.weekSelection.weekOffset
                        , "weekStart" Aeson..= payload.weekSelection.weekStart
                        , "weekEnd" Aeson..= payload.weekSelection.weekEnd
                        , "entryCount" Aeson..= payload.entryCount
                        , "rowCount" Aeson..= payload.rowCount
                        , "payConfigSnapshotVersion" Aeson..= payload.exportSnapshotVersion
                        , "deliveryMethod" Aeson..= exportJob.deliveryMethod
                        ]
                    )

                pure exportJob

            pure (Right exportJob)

requestHourlyBreakdownZipExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    VenueReportDefinition ->
    Int ->
    IO (Either Text ExportJob)
requestHourlyBreakdownZipExport reportDefinition selectedWeekOffset = do
    payloadResult <- buildHourlyBreakdownZipPayload reportDefinition selectedWeekOffset
    case payloadResult of
        Left err -> pure (Left err)
        Right payload -> do
            exportJob <- withTransaction do
                now <- getCurrentTime
                let expiresAt = addUTCTime exportExpirySeconds now
                let exportType = exportJobTypeToText HourlyBreakdownZip
                let initialScope = buildHourlyBreakdownZipScope reportDefinition payload
                exportJob <-
                    newRecord @ExportJob
                        |> set #venueId (unpackId currentVenueId)
                        |> set #requestedByUserId (unpackId (get #id authenticatedCurrentUser))
                        |> set #exportType exportType
                        |> set #status (exportJobStatusToText ExportPending)
                        |> set #schemaVersion exportSchemaVersion
                        |> set #rangeStart (Just payload.weekSelection.weekStart)
                        |> set #rangeEnd (Just payload.weekSelection.weekEnd)
                        |> set #scope initialScope
                        |> set #deliveryMethod browserDownloadMethod
                        |> set #destinationMetadata (Aeson.object ["requestedVia" Aeson..= requestAuditSourceChannel])
                        |> set #expiresAt expiresAt
                        |> createRecord

                exportJob <-
                    exportJob
                        |> set #status (exportJobStatusToText ExportReady)
                        |> set #payConfigSnapshotVersion payload.exportSnapshotVersion
                        |> set #scope initialScope
                        |> set #fileName (Just payload.fileName)
                        |> set #contentType (Just "application/zip")
                        |> set #fileEncoding "base64"
                        |> set #fileContents (Just payload.zipContentsBase64)
                        |> updateRecord

                void $ recordCurrentUserAuditEvent
                    "export_generated"
                    "export_jobs"
                    (unpackId (get #id exportJob))
                    (Aeson.object
                        [ "exportType" Aeson..= exportType
                        , "reportSlug" Aeson..= reportDefinition.definition.slug
                        , "reportEngine" Aeson..= reportDefinitionEngineToText reportDefinition.engine
                        , "weekOffset" Aeson..= payload.weekSelection.weekOffset
                        , "weekStart" Aeson..= payload.weekSelection.weekStart
                        , "weekEnd" Aeson..= payload.weekSelection.weekEnd
                        , "entryCount" Aeson..= payload.entryCount
                        , "fileCount" Aeson..= payload.fileCount
                        , "payConfigSnapshotVersion" Aeson..= payload.exportSnapshotVersion
                        , "deliveryMethod" Aeson..= exportJob.deliveryMethod
                        ]
                    )

                pure exportJob

            pure (Right exportJob)

requestPayrollEarningsCsvExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    VenueReportDefinition ->
    Int ->
    IO (Either Text ExportJob)
requestPayrollEarningsCsvExport reportDefinition selectedWeekOffset = do
    payloadResult <- buildPayrollEarningsCsvPayload reportDefinition selectedWeekOffset
    case payloadResult of
        Left err -> pure (Left err)
        Right payload -> do
            exportJob <- withTransaction do
                now <- getCurrentTime
                let expiresAt = addUTCTime exportExpirySeconds now
                let exportType = exportJobTypeToText PayrollEarningsCsv
                let initialScope = buildPayrollEarningsCsvScope reportDefinition payload
                exportJob <-
                    newRecord @ExportJob
                        |> set #venueId (unpackId currentVenueId)
                        |> set #requestedByUserId (unpackId (get #id authenticatedCurrentUser))
                        |> set #exportType exportType
                        |> set #status (exportJobStatusToText ExportPending)
                        |> set #schemaVersion exportSchemaVersion
                        |> set #rangeStart (Just payload.weekSelection.weekStart)
                        |> set #rangeEnd (Just payload.weekSelection.weekEnd)
                        |> set #scope initialScope
                        |> set #deliveryMethod browserDownloadMethod
                        |> set #destinationMetadata (Aeson.object ["requestedVia" Aeson..= requestAuditSourceChannel])
                        |> set #expiresAt expiresAt
                        |> createRecord

                exportJob <-
                    exportJob
                        |> set #status (exportJobStatusToText ExportReady)
                        |> set #payConfigSnapshotVersion payload.exportSnapshotVersion
                        |> set #scope initialScope
                        |> set #fileName (Just payload.fileName)
                        |> set #contentType (Just "text/csv; charset=utf-8")
                        |> set #fileEncoding "utf8"
                        |> set #fileContents (Just payload.csvContents)
                        |> updateRecord

                void $ recordCurrentUserAuditEvent
                    "export_generated"
                    "export_jobs"
                    (unpackId (get #id exportJob))
                    (Aeson.object
                        [ "exportType" Aeson..= exportType
                        , "reportSlug" Aeson..= reportDefinition.definition.slug
                        , "reportEngine" Aeson..= reportDefinitionEngineToText reportDefinition.engine
                        , "weekOffset" Aeson..= payload.weekSelection.weekOffset
                        , "weekStart" Aeson..= payload.weekSelection.weekStart
                        , "weekEnd" Aeson..= payload.weekSelection.weekEnd
                        , "entryCount" Aeson..= payload.entryCount
                        , "rowCount" Aeson..= payload.rowCount
                        , "payConfigSnapshotVersion" Aeson..= payload.exportSnapshotVersion
                        , "deliveryMethod" Aeson..= exportJob.deliveryMethod
                        ]
                    )

                pure exportJob

            pure (Right exportJob)

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
    snapshotVersionsByEntryId <- fetchSnapshotVersionsForEntries entries
    let filteredEntries = filter (shouldIncludeStaffPayEntry reportDefinition staffById) entries
    let missingEntryIds =
            map (tshow . get #id) $
                filter (\entry -> Map.notMember (timesheetEntryIdKey (get #id entry)) payResultsByEntryId) filteredEntries

    if not (null missingEntryIds)
        then pure (Left "Failed to resolve payroll data for one or more approved timesheet entries.")
        else do
            let records = buildStaffPayCsvRecords reportDefinition reportWeekSelection filteredEntries staffById payResultsByEntryId
            let exportSnapshotVersions =
                    filteredEntries
                        |> mapMaybe (\entry -> entry.payConfigSnapshotId >>= (`Map.lookup` snapshotVersionsByEntryId))
                        |> List.nub
                        |> List.sort
            let exportSnapshotVersion =
                    case exportSnapshotVersions of
                        []             -> Nothing
                        [versionLabel] -> Just versionLabel
                        _              -> Just "mixed"
            pure $
                Right
                    StaffPayCsvPayload
                        { weekSelection = reportWeekSelection
                        , fileName = reportDefinition.definition.slug <> "-" <> tshow reportWeekSelection.weekStart <> ".csv"
                        , csvContents = renderStaffPayCsv reportWeekSelection records
                        , entryCount = length filteredEntries
                        , rowCount = length records
                        , snapshotVersions = exportSnapshotVersions
                        , exportSnapshotVersion
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
        , "snapshotVersions" Aeson..= payload.snapshotVersions
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
    snapshotVersionsByEntryId <- fetchSnapshotVersionsForEntries entries
    let filteredEntries = filter (shouldIncludeStaffPayEntry reportDefinition staffById) entries
    let missingEntryIds =
            map (tshow . get #id) $
                filter (\entry -> Map.notMember (timesheetEntryIdKey (get #id entry)) payResultsByEntryId) filteredEntries

    if not (null missingEntryIds)
        then pure (Left "Failed to resolve payroll data for one or more approved timesheet entries.")
        else do
            let records = buildPayrollEarningsCsvRecords filteredEntries staffById payResultsByEntryId snapshotVersionsByEntryId
            let exportSnapshotVersions =
                    filteredEntries
                        |> mapMaybe (\entry -> entry.payConfigSnapshotId >>= (`Map.lookup` snapshotVersionsByEntryId))
                        |> List.nub
                        |> List.sort
            let exportSnapshotVersion =
                    case exportSnapshotVersions of
                        []             -> Nothing
                        [versionLabel] -> Just versionLabel
                        _              -> Just "mixed"
            pure $
                Right
                    PayrollEarningsCsvPayload
                        { weekSelection = reportWeekSelection
                        , fileName = reportDefinition.definition.slug <> "-" <> tshow reportWeekSelection.weekStart <> ".csv"
                        , csvContents = renderPayrollEarningsCsv records
                        , entryCount = length filteredEntries
                        , rowCount = length records
                        , snapshotVersions = exportSnapshotVersions
                        , exportSnapshotVersion
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
        , "snapshotVersions" Aeson..= payload.snapshotVersions
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
    snapshotVersionsByEntryId <- fetchSnapshotVersionsForEntries filteredEntries
    shiftTypes <- fetchCurrentVenueReportShiftTypes reportDefinition
    let snapshotVersions =
            filteredEntries
                |> mapMaybe (\entry -> entry.payConfigSnapshotId >>= (`Map.lookup` snapshotVersionsByEntryId))
                |> List.nub
                |> List.sort
    let exportSnapshotVersion =
            case snapshotVersions of
                []             -> Nothing
                [versionLabel] -> Just versionLabel
                _              -> Just "mixed"
    let zipContentsBase64 = renderHourlyBreakdownZipBase64 reportWeekSelection shiftTypes filteredEntries
    pure $
        Right
            HourlyBreakdownZipPayload
                { weekSelection = reportWeekSelection
                , fileName = reportDefinition.definition.slug <> "-" <> tshow reportWeekSelection.weekStart <> ".zip"
                , zipContentsBase64
                , entryCount = length filteredEntries
                , fileCount = length reportWeekSelection.dayLabels
                , snapshotVersions
                , exportSnapshotVersion
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
        , "snapshotVersions" Aeson..= payload.snapshotVersions
        , "filterShiftTypes" Aeson..= map (.name) reportDefinition.shiftTypeFilters
        ]

fetchReportStaffMap :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID Staff)
fetchReportStaffMap entries =
    if null staffIds
        then pure Map.empty
        else do
            staffMembers <- query @Staff
                |> filterWhereIn (#id, map Id staffIds)
                |> filterWhere (#isActive, True)
                |> fetch
            pure (Map.fromList (map (\staff -> (coerce (get #id staff), staff)) staffMembers))
    where
        staffIds = List.nub (map (.staffId) entries)

fetchCurrentVenueReportShiftTypes ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    VenueReportDefinition ->
    IO [ShiftType]
fetchCurrentVenueReportShiftTypes reportDefinition =
    if null allowedShiftTypeIds
        then query @ShiftType
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#isActive, True)
            |> orderByAsc #sortOrder
            |> orderByAsc #name
            |> fetch
        else query @ShiftType
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhereIn (#id, map Id allowedShiftTypeIds)
            |> orderByAsc #sortOrder
            |> orderByAsc #name
            |> fetch
    where
        allowedShiftTypeIds = map (coerce . get #id) reportDefinition.shiftTypeFilters

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
    { aggregationStaffFirstName       :: !Text
    , aggregationStaffLastName        :: !Text
    , aggregationWorkDate             :: !Day
    , aggregationEarningsRateName     :: !Text
    , aggregationTrackingCode         :: !(Maybe Text)
    , aggregationMinutes              :: !Int
    , aggregationStaffId              :: !UUID
    , aggregationTimesheetEntryIds    :: ![UUID]
    , aggregationSnapshotVersions     :: ![Text]
    , aggregationSourcePenaltyKind    :: !Text
    , aggregationSourcePayLevelName   :: !(Maybe Text)
    , aggregationSourceShiftTypeName  :: !(Maybe Text)
    }
    deriving (Eq, Show)

buildPayrollEarningsCsvRecords ::
    [TimesheetEntry] ->
    Map.Map UUID Staff ->
    Map.Map Text TimesheetPayResult ->
    Map.Map UUID Text ->
    [PayrollEarningsCsvRecord]
buildPayrollEarningsCsvRecords entries staffById payResultsByEntryId snapshotVersionsByEntryId =
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
                            snapshotVersions = maybeToList (entry.payConfigSnapshotId >>= (`Map.lookup` snapshotVersionsByEntryId))
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
                                    , aggregationSnapshotVersions = snapshotVersions
                                    , aggregationSourcePenaltyKind = sourcePenaltyKind
                                    , aggregationSourcePayLevelName = sourcePayLevelName
                                    , aggregationSourceShiftTypeName = sourceShiftTypeName
                                    }
                         in Map.insertWith mergeAggregation key newAggregation acc

        mergeAggregation new old =
            old
                { aggregationMinutes = old.aggregationMinutes + new.aggregationMinutes
                , aggregationTimesheetEntryIds = List.sort (List.nub (old.aggregationTimesheetEntryIds <> new.aggregationTimesheetEntryIds))
                , aggregationSnapshotVersions = List.sort (List.nub (old.aggregationSnapshotVersions <> new.aggregationSnapshotVersions))
                }

        toRecord aggregation =
            PayrollEarningsCsvRecord
                { staffFirstName = aggregation.aggregationStaffFirstName
                , staffLastName = aggregation.aggregationStaffLastName
                , workDate = aggregation.aggregationWorkDate
                , earningsRateName = aggregation.aggregationEarningsRateName
                , hours = paidMinutesToHours aggregation.aggregationMinutes
                , trackingCode = aggregation.aggregationTrackingCode
                , description = "IHP entries: " <> Text.intercalate " " (map tshow aggregation.aggregationTimesheetEntryIds)
                , staffId = aggregation.aggregationStaffId
                , timesheetEntryIds = aggregation.aggregationTimesheetEntryIds
                , payConfigSnapshot = snapshotVersionForAggregation aggregation.aggregationSnapshotVersions
                , sourcePenaltyKind = aggregation.aggregationSourcePenaltyKind
                , sourcePayLevelName = aggregation.aggregationSourcePayLevelName
                , sourceShiftTypeName = aggregation.aggregationSourceShiftTypeName
                }

        snapshotVersionForAggregation snapshotVersions =
            case List.nub snapshotVersions of
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
        "saturday_penalty" -> "Saturday"
        "sunday_penalty" -> "Sunday"
        "public_holiday_penalty" -> "Public Holiday"
        "evening_after_7pm" -> "Evening After 7pm"
        "late_night_after_midnight" -> "Late Night After Midnight"
        _ -> "Ordinary"

requestApprovedTimesheetsCsvExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO ExportJob
requestApprovedTimesheetsCsvExport rangeStart rangeEnd = withTransaction do
    now <- getCurrentTime
    let expiresAt = addUTCTime exportExpirySeconds now
    let exportType = exportJobTypeToText ApprovedTimesheetsCsv
    _ <- ensureCurrentVenuePayConfigSnapshot
    let initialScope =
            Aeson.object
                [ "rangeStart" Aeson..= rangeStart
                , "rangeEnd" Aeson..= rangeEnd
                , "approvedOnly" Aeson..= True
                ]
    exportJob <-
        newRecord @ExportJob
            |> set #venueId (unpackId currentVenueId)
            |> set #requestedByUserId (unpackId (get #id authenticatedCurrentUser))
            |> set #exportType exportType
            |> set #status (exportJobStatusToText ExportPending)
            |> set #schemaVersion exportSchemaVersion
            |> set #rangeStart (Just rangeStart)
            |> set #rangeEnd (Just rangeEnd)
            |> set #scope initialScope
            |> set #deliveryMethod browserDownloadMethod
            |> set #destinationMetadata (Aeson.object ["requestedVia" Aeson..= requestAuditSourceChannel])
            |> set #expiresAt expiresAt
            |> createRecord

    entries <- fetchApprovedTimesheetEntries rangeStart rangeEnd
    staffById <- fetchStaffMap entries
    approversById <- fetchApproverMap entries
    snapshotVersionsByEntryId <- fetchSnapshotVersionsForEntries entries
    let snapshotVersions = List.sort (List.nub (Map.elems snapshotVersionsByEntryId))
    let exportSnapshotVersion =
            case snapshotVersions of
                []             -> Nothing
                [versionLabel] -> Just versionLabel
                _              -> Just "mixed"
    let csvContents = renderApprovedTimesheetCsv entries staffById approversById snapshotVersionsByEntryId
    let fileName = buildApprovedTimesheetExportFileName rangeStart rangeEnd
    let finalScope =
            Aeson.object
                [ "rangeStart" Aeson..= rangeStart
                , "rangeEnd" Aeson..= rangeEnd
                , "approvedOnly" Aeson..= True
                , "entryCount" Aeson..= length entries
                , "snapshotVersions" Aeson..= snapshotVersions
                ]
    exportJob <-
        exportJob
            |> set #status (exportJobStatusToText ExportReady)
            |> set #payConfigSnapshotVersion exportSnapshotVersion
            |> set #scope finalScope
            |> set #fileName (Just fileName)
            |> set #contentType (Just "text/csv; charset=utf-8")
            |> set #fileEncoding "utf8"
            |> set #fileContents (Just csvContents)
            |> updateRecord

    void $ recordCurrentUserAuditEvent
        "export_generated"
        "export_jobs"
        (unpackId (get #id exportJob))
        (Aeson.object
            [ "exportType" Aeson..= exportType
            , "rangeStart" Aeson..= rangeStart
            , "rangeEnd" Aeson..= rangeEnd
            , "entryCount" Aeson..= length entries
            , "payConfigSnapshotVersion" Aeson..= exportSnapshotVersion
            , "deliveryMethod" Aeson..= exportJob.deliveryMethod
            ]
        )

    pure exportJob

expireCurrentVenueExportJobs :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
expireCurrentVenueExportJobs = do
    now <- getCurrentTime
    exportJobs <- query @ExportJob
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetch

    forM_ exportJobs \exportJob ->
        when (shouldExpireExportJob now exportJob) do
            exportJob
                |> set #status (exportJobStatusToText ExportExpired)
                |> updateRecordDiscardResult

fetchCurrentVenueExportJobs :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ExportJob]
fetchCurrentVenueExportJobs = do
    expireCurrentVenueExportJobs
    query @ExportJob
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> orderByDesc #createdAt
        |> fetch

authorizeExportDownload ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Id ExportJob ->
    UUID ->
    IO ExportJob
authorizeExportDownload exportJobId downloadToken = do
    exportJob <- fetch exportJobId
    ensureRecordInCurrentVenue exportJob.venueId
    accessDeniedUnless (exportJob.downloadToken == downloadToken)

    now <- getCurrentTime
    when (shouldExpireExportJob now exportJob) do
        exportJob
            |> set #status (exportJobStatusToText ExportExpired)
            |> updateRecordDiscardResult
        accessDeniedUnless False

    accessDeniedUnless (exportJob.status == exportJobStatusToText ExportReady)
    accessDeniedUnless (isJust exportJob.fileContents)
    pure exportJob

recordExportDownload ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    ExportJob ->
    IO ExportJob
recordExportDownload exportJob = withTransaction do
    now <- getCurrentTime
    exportJob <-
        exportJob
            |> set #downloadedAt (Just now)
            |> set #downloadedByUserId (Just (unpackId (get #id authenticatedCurrentUser)))
            |> updateRecord

    void $ recordCurrentUserAuditEvent
        "export_downloaded"
        "export_jobs"
        (unpackId (get #id exportJob))
        (Aeson.object
            [ "exportType" Aeson..= exportJob.exportType
            , "generatedFileId" Aeson..= exportJob.generatedFileId
            , "deliveryMethod" Aeson..= exportJob.deliveryMethod
            ]
        )

    pure exportJob

buildApprovedTimesheetExportFileName :: Day -> Day -> Text
buildApprovedTimesheetExportFileName rangeStart rangeEnd =
    "approved-timesheets-" <> tshow rangeStart <> "-to-" <> tshow rangeEnd <> ".csv"

fetchApprovedTimesheetEntries ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO [TimesheetEntry]
fetchApprovedTimesheetEntries rangeStart rangeEnd =
    query @TimesheetEntry
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isApproved, True)
        |> filterWhereIn (#workedOn, [rangeStart .. rangeEnd])
        |> orderByAsc #workedOn
        |> orderByAsc #startTime
        |> fetch

fetchStaffMap :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID Staff)
fetchStaffMap entries =
    if null staffIds
        then pure Map.empty
        else do
            staff <- query @Staff |> filterWhereIn (#id, map Id staffIds) |> fetch
            pure (Map.fromList (map (\staffMember -> (coerce (get #id staffMember), staffMember)) staff))
    where
        staffIds = List.nub (map (.staffId) entries)

fetchApproverMap :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID User)
fetchApproverMap entries =
    if null approverIds
        then pure Map.empty
        else do
            users <- query @User |> filterWhereIn (#id, map Id approverIds) |> fetch
            pure (Map.fromList (map (\user -> (coerce (get #id user), user)) users))
    where
        approverIds = List.nub (mapMaybe (.approvedByUserId) entries)

fetchSnapshotVersionsForEntries :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID Text)
fetchSnapshotVersionsForEntries entries =
    if null snapshotIds
        then pure Map.empty
        else do
            snapshots <- query @PayConfigSnapshot |> filterWhereIn (#id, map Id snapshotIds) |> fetch
            pure (Map.fromList (map (\snapshot -> (coerce (get #id snapshot), snapshot.versionLabel)) snapshots))
    where
        snapshotIds = List.nub (mapMaybe (.payConfigSnapshotId) entries)

shouldExpireExportJob :: UTCTime -> ExportJob -> Bool
shouldExpireExportJob now exportJob =
    exportJob.status /= exportJobStatusToText ExportExpired
        && exportJob.expiresAt <= now

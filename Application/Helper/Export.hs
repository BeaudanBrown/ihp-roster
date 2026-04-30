module Application.Helper.Export
    ( module Application.Helper.Export
    , module Application.Helper.Export.Types
    , module Application.Helper.Export.Render
    ) where

import Application.Helper.Controller
import Application.Helper.Export.Render
import Application.Helper.Export.Types
import Application.Helper.Pay (PaySegment (..), PayTotals (..),
                               TimesheetPayResult (..),
                               collapsePayVersionManifests,
                               fetchTimesheetPayResultsForEntries,
                               payVersionManifestForEntry, timesheetEntryIdKey)
import Application.Helper.View (isTrialStaff)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays)
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

requestFixedExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    ExportJobType ->
    Day ->
    Day ->
    IO (Either Text ExportJob)
requestFixedExport exportType rangeStart rangeEnd
    | rangeStart > rangeEnd = pure (Left "Choose a valid start and end date for the export range.")
    | otherwise =
        case exportType of
            ApprovedTimesheetsCsv -> Right <$> requestApprovedTimesheetsCsvExport rangeStart rangeEnd
            StaffPayCsv -> requestFixedStaffPayCsvExport rangeStart rangeEnd
            HourlyBreakdownZip -> requestFixedHourlyBreakdownZipExport rangeStart rangeEnd
            PayrollEarningsCsv -> requestFixedPayrollEarningsCsvExport rangeStart rangeEnd

requestFixedStaffPayCsvExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO (Either Text ExportJob)
requestFixedStaffPayCsvExport rangeStart rangeEnd = do
    weekSelections <- rangeWeekSlices rangeStart rangeEnd
    payloadResults <- mapM buildFixedStaffPayCsvPayload weekSelections
    case lefts payloadResults of
        err : _ -> pure (Left err)
        [] -> do
            let payloads = rights payloadResults
            exportJob <- persistFixedStaffPayExport rangeStart rangeEnd payloads
            pure (Right exportJob)

persistFixedStaffPayExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    [StaffPayCsvPayload] ->
    IO ExportJob
persistFixedStaffPayExport rangeStart rangeEnd payloads = withTransaction do
    now <- getCurrentTime
    let expiresAt = addUTCTime exportExpirySeconds now
    let exportType = exportJobTypeToText StaffPayCsv
    let versionManifests = List.sort (List.nub (concatMap (.versionManifests) payloads))
    let exportVersionManifest = collapseVersionManifests versionManifests
    let entryCount = sum (map (.entryCount) payloads)
    let rowCount = sum (map (.rowCount) payloads)
    let isSingleWeek = length payloads == 1
    let fileName =
            if isSingleWeek
                then "staff_hours-" <> tshow rangeStart <> "-to-" <> tshow rangeEnd <> ".csv"
                else "staff_hours-" <> tshow rangeStart <> "-to-" <> tshow rangeEnd <> ".zip"
    let fileContents =
            case payloads of
                [payload] -> payload.csvContents
                _ -> renderTextZipBase64
                        [ ( weeklyFolderName payload.weekSelection <> "/staff_hours.csv"
                          , payload.csvContents
                          )
                        | payload <- payloads
                        ]
    let contentType =
            if isSingleWeek
                then "text/csv; charset=utf-8"
                else "application/zip"
    let fileEncoding =
            if isSingleWeek
                then "utf8"
                else "base64"
    persistReadyExportJob
        exportType
        rangeStart
        rangeEnd
        (Aeson.object
            [ "rangeStart" Aeson..= rangeStart
            , "rangeEnd" Aeson..= rangeEnd
            , "approvedOnly" Aeson..= True
            , "entryCount" Aeson..= entryCount
            , "rowCount" Aeson..= rowCount
            , "versionManifests" Aeson..= versionManifests
            , "packaging" Aeson..= if isSingleWeek then ("csv" :: Text) else "zip_weekly_csv"
            ])
        fileName
        contentType
        fileEncoding
        fileContents
        exportVersionManifest
        expiresAt
        (Aeson.object
            [ "exportType" Aeson..= exportType
            , "rangeStart" Aeson..= rangeStart
            , "rangeEnd" Aeson..= rangeEnd
            , "entryCount" Aeson..= entryCount
            , "rowCount" Aeson..= rowCount
            , "payConfigVersionManifest" Aeson..= exportVersionManifest
            , "deliveryMethod" Aeson..= browserDownloadMethod
            ])

requestFixedHourlyBreakdownZipExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO (Either Text ExportJob)
requestFixedHourlyBreakdownZipExport rangeStart rangeEnd = do
    entries <- fetchApprovedTimesheetEntries rangeStart rangeEnd
    shiftTypes <- fetchCurrentVenueActiveShiftTypes
    versionManifestsByEntryId <- fetchVersionManifestsForEntries entries
    let dates = [rangeStart .. rangeEnd]
    let versionManifests = List.sort (List.nub (Map.elems versionManifestsByEntryId))
    let exportVersionManifest = collapseVersionManifests versionManifests
    let fileName = "hourly_breakdown-" <> tshow rangeStart <> "-to-" <> tshow rangeEnd <> ".zip"
    let fileContents =
            renderTextZipBase64
                [ (tshow date <> "_" <> fallbackReportDayLabel date 0 <> ".csv", renderHourlyBreakdownDateCsv date shiftTypes entries)
                | date <- dates
                ]
    exportJob <- withTransaction do
        now <- getCurrentTime
        persistReadyExportJob
            (exportJobTypeToText HourlyBreakdownZip)
            rangeStart
            rangeEnd
            (Aeson.object
                [ "rangeStart" Aeson..= rangeStart
                , "rangeEnd" Aeson..= rangeEnd
                , "approvedOnly" Aeson..= True
                , "entryCount" Aeson..= length entries
                , "fileCount" Aeson..= length dates
                , "versionManifests" Aeson..= versionManifests
                ])
            fileName
            "application/zip"
            "base64"
            fileContents
            exportVersionManifest
            (addUTCTime exportExpirySeconds now)
            (Aeson.object
                [ "exportType" Aeson..= exportJobTypeToText HourlyBreakdownZip
                , "rangeStart" Aeson..= rangeStart
                , "rangeEnd" Aeson..= rangeEnd
                , "entryCount" Aeson..= length entries
                , "fileCount" Aeson..= length dates
                , "payConfigVersionManifest" Aeson..= exportVersionManifest
                , "deliveryMethod" Aeson..= browserDownloadMethod
                ])
    pure (Right exportJob)

requestFixedPayrollEarningsCsvExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO (Either Text ExportJob)
requestFixedPayrollEarningsCsvExport rangeStart rangeEnd = do
    entries <- fetchApprovedTimesheetEntries rangeStart rangeEnd
    staffById <- fetchReportStaffMap entries
    payResultsByEntryId <- fetchTimesheetPayResultsForEntries entries
    versionManifestsByEntryId <- fetchVersionManifestsForEntries entries
    let filteredEntries = filter (shouldIncludeFixedStaffPayEntry staffById) entries
    let missingEntryIds =
            map (tshow . get #id) $
                filter (\entry -> Map.notMember (timesheetEntryIdKey (get #id entry)) payResultsByEntryId) filteredEntries

    if not (null missingEntryIds)
        then pure (Left "Failed to resolve payroll data for one or more approved timesheet entries.")
        else do
            let records = buildPayrollEarningsCsvRecords filteredEntries staffById payResultsByEntryId versionManifestsByEntryId
            let versionManifests =
                    filteredEntries
                        |> mapMaybe (\entry -> Map.lookup (coerce (get #id entry)) versionManifestsByEntryId)
                        |> List.nub
                        |> List.sort
            let exportVersionManifest = collapseVersionManifests versionManifests
            let fileName = "payroll_earnings-" <> tshow rangeStart <> "-to-" <> tshow rangeEnd <> ".csv"
            exportJob <- withTransaction do
                now <- getCurrentTime
                persistReadyExportJob
                    (exportJobTypeToText PayrollEarningsCsv)
                    rangeStart
                    rangeEnd
                    (Aeson.object
                        [ "rangeStart" Aeson..= rangeStart
                        , "rangeEnd" Aeson..= rangeEnd
                        , "approvedOnly" Aeson..= True
                        , "entryCount" Aeson..= length filteredEntries
                        , "rowCount" Aeson..= length records
                        , "versionManifests" Aeson..= versionManifests
                        ])
                    fileName
                    "text/csv; charset=utf-8"
                    "utf8"
                    (renderPayrollEarningsCsv records)
                    exportVersionManifest
                    (addUTCTime exportExpirySeconds now)
                    (Aeson.object
                        [ "exportType" Aeson..= exportJobTypeToText PayrollEarningsCsv
                        , "rangeStart" Aeson..= rangeStart
                        , "rangeEnd" Aeson..= rangeEnd
                        , "entryCount" Aeson..= length filteredEntries
                        , "rowCount" Aeson..= length records
                        , "payConfigVersionManifest" Aeson..= exportVersionManifest
                        , "deliveryMethod" Aeson..= browserDownloadMethod
                        ])
            pure (Right exportJob)

fetchCurrentVenueReportDefinitions ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO [VenueReportDefinition]
fetchCurrentVenueReportDefinitions =
    filter (.definition.isActive) <$> fetchCurrentVenueReportDefinitionsIncludingInactive

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
            _ <- createReportDefinition "wage" "Wage Report" (Just "Hourly staff count breakdown per day (ZIP of CSVs)") HourlyBreakdownZipReport 10
            _ <- createReportDefinition "staff_hours" "Staff Hours Report" (Just "Staff hours broken down by pay level and day") StaffPayCsvReport 20
            _ <- createReportDefinition "payroll_earnings" "Payroll Earnings CSV" (Just "Approved payroll earnings by staff, date, earnings bucket, and tracking code") PayrollEarningsCsvReport 25
            forM_ (find (\shiftType -> shiftType.name == "Kitchen") shiftTypes) \kitchenShiftType -> do
                kitchenDefinition <- createReportDefinition "kitchen" "Kitchen Report" (Just "Kitchen staff hours by day") StaffPayCsvReport 30
                newRecord @ReportDefinitionShiftTypeFilter
                    |> set #reportDefinitionId (unpackId (get #id kitchenDefinition))
                    |> set #shiftTypeId (unpackId (get #id kitchenShiftType))
                    |> createRecord
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
                |> filterWhere (#deletedAt, Nothing)
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
                        |> set #payConfigVersionManifest payload.exportVersionManifest
                        |> set #scope initialScope
                        |> set #fileName (Just payload.fileName)
                        |> set #contentType (Just "text/csv; charset=utf-8")
                        |> set #fileEncoding "utf8"
                        |> set #fileContents (Just payload.csvContents)
                        |> updateRecord

                recordExportJobEntriesForRange exportJob payload.weekSelection.weekStart payload.weekSelection.weekEnd

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
                        , "payConfigVersionManifest" Aeson..= payload.exportVersionManifest
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
                        |> set #payConfigVersionManifest payload.exportVersionManifest
                        |> set #scope initialScope
                        |> set #fileName (Just payload.fileName)
                        |> set #contentType (Just "application/zip")
                        |> set #fileEncoding "base64"
                        |> set #fileContents (Just payload.zipContentsBase64)
                        |> updateRecord

                recordExportJobEntriesForRange exportJob payload.weekSelection.weekStart payload.weekSelection.weekEnd

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
                        , "payConfigVersionManifest" Aeson..= payload.exportVersionManifest
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
                        |> set #payConfigVersionManifest payload.exportVersionManifest
                        |> set #scope initialScope
                        |> set #fileName (Just payload.fileName)
                        |> set #contentType (Just "text/csv; charset=utf-8")
                        |> set #fileEncoding "utf8"
                        |> set #fileContents (Just payload.csvContents)
                        |> updateRecord

                recordExportJobEntriesForRange exportJob payload.weekSelection.weekStart payload.weekSelection.weekEnd

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
                        , "payConfigVersionManifest" Aeson..= payload.exportVersionManifest
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
            let exportVersionManifest =
                    case exportVersionManifests of
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
            let exportVersionManifest =
                    case exportVersionManifests of
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
    let exportVersionManifest =
            case versionManifests of
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

rangeWeekSelections ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO [ReportWeekSelection]
rangeWeekSelections rangeStart rangeEnd = do
    map (.weekSelection) <$> rangeWeekSlices rangeStart rangeEnd

rangeWeekSlices ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO [ReportWeekSlice]
rangeWeekSlices rangeStart rangeEnd = do
    venueConfig <- fetchVenueConfig
    let firstWeekStart = venueWeekStartDate venueConfig (venueWeekOffsetForDay venueConfig rangeStart)
    let weekStarts = takeWhile (<= rangeEnd) (iterate (addDays 7) firstWeekStart)
    pure (map (toSlice venueConfig) weekStarts)
    where
        toSlice venueConfig weekStart =
            let weekEnd = addDays 6 weekStart
            in ReportWeekSlice
                { weekSelection =
                    ReportWeekSelection
                        { weekOffset = venueWeekOffsetForDay venueConfig weekStart
                        , weekStart
                        , weekEnd
                        , dayLabels = fallbackReportDayLabels weekStart
                        }
                , sliceStart = max rangeStart weekStart
                , sliceEnd = min rangeEnd weekEnd
                }

data ReportWeekSlice = ReportWeekSlice
    { weekSelection :: ReportWeekSelection
    , sliceStart    :: Day
    , sliceEnd      :: Day
    }

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

fetchCurrentVenueActiveShiftTypes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueActiveShiftTypes =
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> orderByAsc #sortOrder
        |> orderByAsc #name
        |> fetch

persistReadyExportJob ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Text ->
    Day ->
    Day ->
    Aeson.Value ->
    Text ->
    Text ->
    Text ->
    Text ->
    Maybe Text ->
    UTCTime ->
    Aeson.Value ->
    IO ExportJob
persistReadyExportJob exportType rangeStart rangeEnd finalScope fileName contentType fileEncoding fileContents exportVersionManifest expiresAt auditPayload = do
    _ <- pure ()
    exportJob <-
        newRecord @ExportJob
            |> set #venueId (unpackId currentVenueId)
            |> set #requestedByUserId (unpackId (get #id authenticatedCurrentUser))
            |> set #exportType exportType
            |> set #status (exportJobStatusToText ExportPending)
            |> set #schemaVersion exportSchemaVersion
            |> set #rangeStart (Just rangeStart)
            |> set #rangeEnd (Just rangeEnd)
            |> set #scope finalScope
            |> set #deliveryMethod browserDownloadMethod
            |> set #destinationMetadata (Aeson.object ["requestedVia" Aeson..= requestAuditSourceChannel])
            |> set #expiresAt expiresAt
            |> createRecord

    exportJob <-
        exportJob
            |> set #status (exportJobStatusToText ExportReady)
            |> set #payConfigVersionManifest exportVersionManifest
            |> set #scope finalScope
            |> set #fileName (Just fileName)
            |> set #contentType (Just contentType)
            |> set #fileEncoding fileEncoding
            |> set #fileContents (Just fileContents)
            |> updateRecord

    recordExportJobEntriesForRange exportJob rangeStart rangeEnd

    void $ recordCurrentUserAuditEvent
        "export_generated"
        "export_jobs"
        (unpackId (get #id exportJob))
        auditPayload

    pure exportJob

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
                , description = "IHP entries: " <> Text.intercalate " " (map tshow aggregation.aggregationTimesheetEntryIds)
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

requestApprovedTimesheetsCsvExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO ExportJob
requestApprovedTimesheetsCsvExport rangeStart rangeEnd = withTransaction do
    now <- getCurrentTime
    let expiresAt = addUTCTime exportExpirySeconds now
    let exportType = exportJobTypeToText ApprovedTimesheetsCsv
    _ <- pure ()
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
    versionManifestsByEntryId <- fetchVersionManifestsForEntries entries
    let versionManifests = List.sort (List.nub (Map.elems versionManifestsByEntryId))
    let exportVersionManifest =
            case versionManifests of
                []             -> Nothing
                [versionLabel] -> Just versionLabel
                _              -> Just "mixed"
    let csvContents = renderApprovedTimesheetCsv entries staffById approversById versionManifestsByEntryId
    let fileName = buildApprovedTimesheetExportFileName rangeStart rangeEnd
    let finalScope =
            Aeson.object
                [ "rangeStart" Aeson..= rangeStart
                , "rangeEnd" Aeson..= rangeEnd
                , "approvedOnly" Aeson..= True
                , "entryCount" Aeson..= length entries
                , "versionManifests" Aeson..= versionManifests
                ]
    exportJob <-
        exportJob
            |> set #status (exportJobStatusToText ExportReady)
            |> set #payConfigVersionManifest exportVersionManifest
            |> set #scope finalScope
            |> set #fileName (Just fileName)
            |> set #contentType (Just "text/csv; charset=utf-8")
            |> set #fileEncoding "utf8"
            |> set #fileContents (Just csvContents)
            |> updateRecord

    recordExportJobEntries exportJob entries

    void $ recordCurrentUserAuditEvent
        "export_generated"
        "export_jobs"
        (unpackId (get #id exportJob))
        (Aeson.object
            [ "exportType" Aeson..= exportType
            , "rangeStart" Aeson..= rangeStart
            , "rangeEnd" Aeson..= rangeEnd
            , "entryCount" Aeson..= length entries
            , "payConfigVersionManifest" Aeson..= exportVersionManifest
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
        |> filterWhere (#deletedAt, Nothing)
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

fetchVersionManifestsForEntries :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID Text)
fetchVersionManifestsForEntries entries =
    pure (Map.fromList (mapMaybe entryManifest entries))
    where
        entryManifest entry =
            fmap (\manifest -> (coerce (get #id entry), manifest)) (payVersionManifestForEntry entry)

recordExportJobEntriesForRange ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    ExportJob ->
    Day ->
    Day ->
    IO ()
recordExportJobEntriesForRange exportJob rangeStart rangeEnd = do
    entries <- fetchApprovedTimesheetEntries rangeStart rangeEnd
    recordExportJobEntries exportJob entries

recordExportJobEntries :: (?modelContext :: ModelContext) => ExportJob -> [TimesheetEntry] -> IO ()
recordExportJobEntries exportJob entries =
    mapM_ createRecord (mapMaybe exportEntryRecord entries)
    where
        exportEntryRecord entry = do
            staffPayVersionId <- entry.staffPayVersionId
            shiftTypePayVersionId <- entry.shiftTypePayVersionId
            approvedAt <- entry.approvedAt
            pure $
                newRecord @ExportJobEntry
                    |> set #exportJobId (unpackId (get #id exportJob))
                    |> set #timesheetEntryId (unpackId (get #id entry))
                    |> set #staffPayVersionId staffPayVersionId
                    |> set #shiftTypePayVersionId shiftTypePayVersionId
                    |> set #entryUpdatedAtAtExport entry.updatedAt
                    |> set #entryApprovedAtAtExport approvedAt

shouldExpireExportJob :: UTCTime -> ExportJob -> Bool
shouldExpireExportJob now exportJob =
    exportJob.status /= exportJobStatusToText ExportExpired
        && exportJob.expiresAt <= now

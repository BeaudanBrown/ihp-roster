module Application.Helper.Export.Service where

import Application.Helper.Controller
import Application.Helper.Export.Definitions
import Application.Helper.Export.HourlyBreakdown
import Application.Helper.Export.Payloads
import Application.Helper.Export.Persistence
import Application.Helper.Export.ReadModel
import Application.Helper.Export.Render
import Application.Helper.Export.Types
import Application.WageSourceEnforcement (enforceFinalWageEntries,
                                          renderWageEntryFailures)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Data.Time.Clock (addUTCTime, getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude

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
            ApprovedTimesheetsCsv -> requestApprovedTimesheetsCsvExport rangeStart rangeEnd
            StaffPayCsv -> requestFixedStaffPayCsvExport rangeStart rangeEnd
            HourlyBreakdownZip -> requestFixedHourlyBreakdownZipExport rangeStart rangeEnd
            HourlyWageTotalsZip -> requestFixedHourlyWageTotalsZipExport rangeStart rangeEnd
            PayrollEarningsCsv -> requestFixedPayrollEarningsCsvExport rangeStart rangeEnd

requestFixedStaffPayCsvExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO (Either Text ExportJob)
requestFixedStaffPayCsvExport rangeStart rangeEnd = do
    entries <- fetchApprovedTimesheetEntries rangeStart rangeEnd
    staffById <- fetchReportStaffMap entries
    let includedEntries = filter (shouldIncludeFixedStaffPayEntry staffById) entries
    enforceFinalWageEntries includedEntries >>= \case
        Left failures -> pure (Left (renderWageEntryFailures "Payroll output blocked: " failures))
        Right calculations -> do
            venueConfig <- fetchVenueConfig
            sealedWindowStartsByEntryId <- fetchApprovedEntryRosterWindowStarts includedEntries
            let fallbackWindowStart = startOfWeekFor venueConfig.rosterWeekStartsOn rangeStart
            let sealedWindowStarts = Map.elems sealedWindowStartsByEntryId
            let needsFallbackWindows = null includedEntries || any (\entry -> Map.notMember (unpackId entry.id) sealedWindowStartsByEntryId) includedEntries
            let fallbackWindowStarts =
                    if needsFallbackWindows
                        then map (.weekStart) (map (.weekSelection) (rangeWeekSlices rangeStart rangeEnd fallbackWindowStart))
                        else []
            let weekStarts = List.sort (List.nub (sealedWindowStarts <> fallbackWindowStarts))
            let calculationsByEntryId = calculationMap includedEntries calculations
            payloadResults <- mapM (buildFixedStaffPayCsvPayload calculationsByEntryId sealedWindowStartsByEntryId rangeStart rangeEnd) weekStarts
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
            case payloads of
                [payload] -> payload.fileName
                _         -> "staff_hrs-" <> tshow rangeStart <> "-to-" <> tshow rangeEnd <> ".zip"
    let fileContents =
            case payloads of
                [payload] -> payload.csvContents
                _ -> renderTextZipBase64
                        [ ( weeklyFolderName payload.weekSelection <> "/" <> payload.fileName
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
    enforcement <- enforceExportEntries entries
    case enforcement of
        Left message -> pure (Left message)
        Right ()     -> requestWithEnforcedEntries entries
  where
    requestWithEnforcedEntries entries = do
        venueConfig <- fetchVenueConfig
        activeShiftTypes <- fetchCurrentVenueActiveShiftTypes
        reportShiftTypes <- fetchReportShiftTypes entries
        shiftLabelsByEntryId <- fetchApprovedEntryShiftLabels entries
        versionManifestsByEntryId <- fetchVersionManifestsForEntries entries
        let dates = [rangeStart .. rangeEnd]
        let window = buildHourlyReportWindow venueConfig entries
        let columns = buildHourlyShiftTypeColumns activeShiftTypes reportShiftTypes entries shiftLabelsByEntryId
        let versionManifests = List.sort (List.nub (Map.elems versionManifestsByEntryId))
        let exportVersionManifest = collapseVersionManifests versionManifests
        let fileName = "hourly_staff_hours-" <> tshow rangeStart <> "-to-" <> tshow rangeEnd <> ".zip"
        let fileContents =
                renderTextZipBase64
                    [ (tshow date <> "_" <> fallbackReportDayLabel date 0 <> "_staff_hours.csv", renderHourlyBreakdownDateCsv date window columns entries)
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
                    , "configuredWindowStartMinute" Aeson..= venueConfig.timePickerStartMinuteOfDay
                    , "configuredWindowEndMinute" Aeson..= venueConfig.timePickerFinalSelectableMinuteOfDay
                    , "effectiveWindowStartHour" Aeson..= window.hourlyWindowStartHour
                    , "effectiveWindowEndHour" Aeson..= window.hourlyWindowEndHour
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
                    , "effectiveWindowStartHour" Aeson..= window.hourlyWindowStartHour
                    , "effectiveWindowEndHour" Aeson..= window.hourlyWindowEndHour
                    , "payConfigVersionManifest" Aeson..= exportVersionManifest
                    , "deliveryMethod" Aeson..= browserDownloadMethod
                    ])
        pure (Right exportJob)

requestFixedHourlyWageTotalsZipExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO (Either Text ExportJob)
requestFixedHourlyWageTotalsZipExport rangeStart rangeEnd = do
    entries <- fetchApprovedTimesheetEntries rangeStart rangeEnd
    enforceFinalWageEntries entries >>= \case
        Left failures -> pure (Left (renderWageEntryFailures "Payroll output blocked: " failures))
        Right calculations -> requestWithCalculations entries calculations
  where
    requestWithCalculations entries calculations = do
        venueConfig <- fetchVenueConfig
        activeShiftTypes <- fetchCurrentVenueActiveShiftTypes
        reportShiftTypes <- fetchReportShiftTypes entries
        shiftLabelsByEntryId <- fetchApprovedEntryShiftLabels entries
        versionManifestsByEntryId <- fetchVersionManifestsForEntries entries
        let dates = [rangeStart .. rangeEnd]
        let window = buildHourlyReportWindow venueConfig entries
        let columns = buildHourlyShiftTypeColumns activeShiftTypes reportShiftTypes entries shiftLabelsByEntryId
        let calculationsByEntryId = calculationMap entries calculations
        case buildHourlyWageCents entries calculationsByEntryId of
            Left message -> pure (Left ("Hourly wage totals blocked: " <> message))
            Right wageCents -> do
                let versionManifests = List.sort (List.nub (Map.elems versionManifestsByEntryId))
                let exportVersionManifest = collapseVersionManifests versionManifests
                let fileName = "hourly_wage_totals-" <> tshow rangeStart <> "-to-" <> tshow rangeEnd <> ".zip"
                let fileContents =
                        renderTextZipBase64
                            [ (tshow date <> "_" <> fallbackReportDayLabel date 0 <> "_wage_totals.csv", renderHourlyWageTotalsDateCsv date window columns wageCents)
                            | date <- dates
                            ]
                exportJob <- withTransaction do
                    now <- getCurrentTime
                    persistReadyExportJob
                        (exportJobTypeToText HourlyWageTotalsZip)
                        rangeStart
                        rangeEnd
                        (Aeson.object
                            [ "rangeStart" Aeson..= rangeStart
                            , "rangeEnd" Aeson..= rangeEnd
                            , "approvedOnly" Aeson..= True
                            , "entryCount" Aeson..= length entries
                            , "fileCount" Aeson..= length dates
                            , "configuredWindowStartMinute" Aeson..= venueConfig.timePickerStartMinuteOfDay
                            , "configuredWindowEndMinute" Aeson..= venueConfig.timePickerFinalSelectableMinuteOfDay
                            , "effectiveWindowStartHour" Aeson..= window.hourlyWindowStartHour
                            , "effectiveWindowEndHour" Aeson..= window.hourlyWindowEndHour
                            , "versionManifests" Aeson..= versionManifests
                            ])
                        fileName
                        "application/zip"
                        "base64"
                        fileContents
                        exportVersionManifest
                        (addUTCTime exportExpirySeconds now)
                        (Aeson.object
                            [ "exportType" Aeson..= exportJobTypeToText HourlyWageTotalsZip
                            , "rangeStart" Aeson..= rangeStart
                            , "rangeEnd" Aeson..= rangeEnd
                            , "entryCount" Aeson..= length entries
                            , "fileCount" Aeson..= length dates
                            , "effectiveWindowStartHour" Aeson..= window.hourlyWindowStartHour
                            , "effectiveWindowEndHour" Aeson..= window.hourlyWindowEndHour
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
    versionManifestsByEntryId <- fetchVersionManifestsForEntries entries
    labelsByEntryId <- fetchApprovedEntryPayLabels entries
    shiftLabelsByEntryId <- fetchApprovedEntryShiftLabels entries
    let filteredEntries = filter (shouldIncludeFixedStaffPayEntry staffById) entries

    enforceFinalWageEntries filteredEntries >>= \case
        Left failures -> pure (Left (renderWageEntryFailures "Payroll output blocked: " failures))
        Right calculations -> do
            let calculationsByEntryId = calculationMap filteredEntries calculations
                records = buildPayrollEarningsCsvRecords filteredEntries staffById calculationsByEntryId labelsByEntryId shiftLabelsByEntryId versionManifestsByEntryId
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

requestApprovedTimesheetsCsvExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO (Either Text ExportJob)
requestApprovedTimesheetsCsvExport rangeStart rangeEnd = do
    entries <- fetchApprovedTimesheetEntries rangeStart rangeEnd
    enforceExportEntries entries >>= \case
        Left message -> pure (Left message)
        Right () -> Right <$> persistExport entries
  where
    persistExport entries = withTransaction do
        now <- getCurrentTime
        let expiresAt = addUTCTime exportExpirySeconds now
        let exportType = exportJobTypeToText ApprovedTimesheetsCsv
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
                |> set #destinationMetadata (Aeson.object ["requestedVia" Aeson..= auditSourceChannelText requestAuditSourceChannel])
                |> set #expiresAt expiresAt
                |> createRecord

        staffById <- fetchStaffMap entries
        approversById <- fetchApproverMap entries
        versionManifestsByEntryId <- fetchVersionManifestsForEntries entries
        let versionManifests = List.sort (List.nub (Map.elems versionManifestsByEntryId))
        let exportVersionManifest = collapseVersionManifests versionManifests
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
            ExportGeneratedAudit
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

enforceExportEntries :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Either Text ())
enforceExportEntries entries =
    enforceFinalWageEntries entries >>= \case
        Left failures -> pure (Left (renderWageEntryFailures "Payroll output blocked: " failures))
        Right _       -> pure (Right ())

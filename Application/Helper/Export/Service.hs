module Application.Helper.Export.Service where

import Application.Helper.Controller
import Application.Helper.Export.Definitions
import Application.Helper.Export.HourlyBreakdown
import Application.Helper.Export.Payloads
import Application.Helper.Export.PayrollWorkbook
import Application.Helper.Export.PayrollWorkbookModel
import Application.Helper.Export.Persistence
import Application.Helper.Export.ReadModel
import Application.Helper.Export.Render
import Application.Helper.Export.Types
import Application.Helper.Telemetry (withExportTelemetrySpan)
import Application.VenueTime.Model (decodeTimesheetTiming)
import Application.WageSourceEnforcement (enforceFinalWageEntries,
                                          renderWageEntryFailures)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import Data.Either (isRight)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Data.Time.Clock (addUTCTime, getCurrentTime)
import Data.Traversable (traverse)
import Generated.Types
import IHP.ControllerPrelude

requestFixedExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    ExportJobType ->
    Day ->
    Day ->
    IO (Either Text ExportJob)
requestFixedExport exportType rangeStart rangeEnd =
    withExportTelemetrySpan (exportJobTypeToText exportType) isRight $
        if rangeStart > rangeEnd
            then pure (Left "Choose a valid start and end date for the export range.")
            else case exportType of
                ApprovedTimesheetsCsv -> requestApprovedTimesheetsCsvExport rangeStart rangeEnd
                StaffPayCsv -> requestFixedStaffPayCsvExport rangeStart rangeEnd
                HourlyBreakdownZip -> requestFixedHourlyBreakdownZipExport rangeStart rangeEnd
                HourlyWageTotalsZip -> requestFixedHourlyWageTotalsZipExport rangeStart rangeEnd
                PayrollEarningsCsv -> requestFixedPayrollEarningsCsvExport rangeStart rangeEnd
                PayrollWorkbookXlsx -> requestPayrollWorkbookXlsxExport rangeStart rangeEnd

requestPayrollWorkbookXlsxExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO (Either Text ExportJob)
requestPayrollWorkbookXlsxExport =
    requestPayrollWorkbookXlsxExportWithDefinition defaultPayrollWorkbookDefinition

requestPayrollWorkbookXlsxExportWithDefinition ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    PayrollWorkbookDefinition ->
    Day ->
    Day ->
    IO (Either Text ExportJob)
requestPayrollWorkbookXlsxExportWithDefinition definition rangeStart rangeEnd = do
    entries <- fetchApprovedTimesheetEntries rangeStart rangeEnd
    staffById <- fetchStaffMap entries
    let includedEntries = filter (shouldIncludeFixedStaffPayEntry staffById) entries
    if null includedEntries
        then pure (Left "No approved payroll entries were found for the Payroll Workbook range.")
        else enforceFinalWageEntries includedEntries >>= \case
            Left failures -> pure (Left (renderWageEntryFailures "Payroll Workbook blocked: " failures))
            Right calculations -> do
                venueConfig <- fetchVenueConfig
                payBucketsByEntryId <- fetchApprovedEntryPayrollPayBuckets includedEntries
                shiftLabelsByEntryId <- fetchApprovedEntryShiftLabels includedEntries
                activeShiftTypes <- fetchCurrentVenueActiveShiftTypes
                reportShiftTypes <- fetchReportShiftTypes includedEntries
                versionManifestsByEntryId <- fetchVersionManifestsForEntries includedEntries
                let shiftTypeColumns = buildHourlyShiftTypeColumns activeShiftTypes reportShiftTypes includedEntries shiftLabelsByEntryId
                let calculationsByEntryId = calculationMap includedEntries calculations
                case buildPayrollWorkbookFactModel rangeStart rangeEnd venueConfig includedEntries staffById payBucketsByEntryId shiftLabelsByEntryId shiftTypeColumns calculationsByEntryId of
                    Left message -> pure (Left message)
                    Right factModel ->
                        case payrollWorkbookFromDefinition definition venueConfig.rosterWeekStartsOn factModel of
                            Left message -> pure (Left message)
                            Right workbook -> persistModel definition includedEntries versionManifestsByEntryId factModel workbook
  where
    persistModel definition includedEntries versionManifestsByEntryId factModel workbook = do
        now <- getCurrentTime
        let exportType = exportJobTypeToText PayrollWorkbookXlsx
        let fileName = "payroll_workbook-" <> tshow rangeStart <> "-to-" <> tshow rangeEnd <> ".xlsx"
        let hourlyModel = payrollWorkbookHourlyModelFromFacts factModel
        let workbookContents = renderPayrollWorkbookBase64 workbook
        let definitionSnapshot = map payrollWorkbookSheetFamilyKey definition.payrollWorkbookDefinitionSheetFamilies
        let versionManifests = List.sort (List.nub (Map.elems versionManifestsByEntryId))
        let exportVersionManifest = collapseVersionManifests versionManifests
        let rowCount = sum (map (length . (.payrollDayRows)) hourlyModel.payrollModelDays)
        exportJob <-
            persistReadyExportJobForEntries
                includedEntries
                exportType
                rangeStart
                rangeEnd
                (Aeson.object
                    [ "rangeStart" Aeson..= rangeStart
                    , "rangeEnd" Aeson..= rangeEnd
                    , "format" Aeson..= ("xlsx" :: Text)
                    , "workbookVersion" Aeson..= (2 :: Int)
                    , "dataModel" Aeson..= ("normalized_hourly_facts_v2" :: Text)
                    , "definitionKey" Aeson..= definition.payrollWorkbookDefinitionKey
                    , "definitionVersion" Aeson..= definition.payrollWorkbookDefinitionVersion
                    , "sheetFamilies" Aeson..= definitionSnapshot
                    , "entryCount" Aeson..= length includedEntries
                    , "factCount" Aeson..= length factModel.payrollFactModelFacts
                    , "rowCount" Aeson..= rowCount
                    , "hourColumnCount" Aeson..= length hourlyModel.payrollModelHourSlots
                    , "effectiveWindowStartHour" Aeson..= hourlyModel.payrollModelWindow.hourlyWindowStartHour
                    , "effectiveWindowEndHour" Aeson..= hourlyModel.payrollModelWindow.hourlyWindowEndHour
                    , "versionManifests" Aeson..= versionManifests
                    ])
                fileName
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                "base64"
                workbookContents
                exportVersionManifest
                (addUTCTime exportExpirySeconds now)
                (Aeson.object
                    [ "exportType" Aeson..= exportType
                    , "rangeStart" Aeson..= rangeStart
                    , "rangeEnd" Aeson..= rangeEnd
                    , "entryCount" Aeson..= length includedEntries
                    , "rowCount" Aeson..= rowCount
                    , "workbookVersion" Aeson..= (1 :: Int)
                    , "definitionKey" Aeson..= definition.payrollWorkbookDefinitionKey
                    , "definitionVersion" Aeson..= definition.payrollWorkbookDefinitionVersion
                    , "sheetFamilies" Aeson..= definitionSnapshot
                    , "payConfigVersionManifest" Aeson..= exportVersionManifest
                    , "deliveryMethod" Aeson..= browserDownloadMethod
                    ])
        pure (Right exportJob)

invalidTimesheetTimingExportMessage :: Text
invalidTimesheetTimingExportMessage = "Export blocked because a Timesheet has invalid timing. Repair and reapprove it before exporting."

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
                        then map ((.weekStart) . (.weekSelection)) (rangeWeekSlices rangeStart rangeEnd fallbackWindowStart)
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
persistFixedStaffPayExport rangeStart rangeEnd payloads = do
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
    venueConfig <- fetchVenueConfig
    enforcement <- enforceExportEntries entries
    case enforcement of
        Left message -> pure (Left message)
        Right () -> case buildHourlyReportWindow venueConfig entries of
            Left _       -> pure (Left invalidTimesheetTimingExportMessage)
            Right window -> requestWithEnforcedEntries venueConfig window entries
  where
    requestWithEnforcedEntries venueConfig window entries = do
        activeShiftTypes <- fetchCurrentVenueActiveShiftTypes
        reportShiftTypes <- fetchReportShiftTypes entries
        shiftLabelsByEntryId <- fetchApprovedEntryShiftLabels entries
        versionManifestsByEntryId <- fetchVersionManifestsForEntries entries
        let dates = [rangeStart .. rangeEnd]
        let columns = buildHourlyShiftTypeColumns activeShiftTypes reportShiftTypes entries shiftLabelsByEntryId
        let versionManifests = List.sort (List.nub (Map.elems versionManifestsByEntryId))
        let exportVersionManifest = collapseVersionManifests versionManifests
        let fileName = "hourly_staff_hours-" <> tshow rangeStart <> "-to-" <> tshow rangeEnd <> ".zip"
        let fileContents =
                renderTextZipBase64
                    [ (tshow date <> "_" <> fallbackReportDayLabel date 0 <> "_staff_hours.csv", renderHourlyBreakdownDateCsv date window columns entries)
                    | date <- dates
                    ]
        exportJob <- do
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
    venueConfig <- fetchVenueConfig
    enforceFinalWageEntries entries >>= \case
        Left failures -> pure (Left (renderWageEntryFailures "Payroll output blocked: " failures))
        Right calculations -> case buildHourlyReportWindow venueConfig entries of
            Left _       -> pure (Left invalidTimesheetTimingExportMessage)
            Right window -> requestWithCalculations venueConfig window entries calculations
  where
    requestWithCalculations venueConfig window entries calculations = do
        activeShiftTypes <- fetchCurrentVenueActiveShiftTypes
        reportShiftTypes <- fetchReportShiftTypes entries
        shiftLabelsByEntryId <- fetchApprovedEntryShiftLabels entries
        versionManifestsByEntryId <- fetchVersionManifestsForEntries entries
        let dates = [rangeStart .. rangeEnd]
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
                exportJob <- do
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
            exportJob <- do
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
        Right () -> case traverse attachTiming entries of
            Left _ -> pure (Left "A timesheet entry has invalid timing. Repair and reapprove it before exporting.")
            Right entriesWithTiming -> Right <$> persistExport entriesWithTiming
  where
    attachTiming entry = (entry,) <$> decodeTimesheetTiming entry
    persistExport entriesWithTiming = do
        let entries = map fst entriesWithTiming
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
        let csvContents = renderApprovedTimesheetCsv entriesWithTiming staffById approversById versionManifestsByEntryId
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

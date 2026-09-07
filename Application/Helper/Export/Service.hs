module Application.Helper.Export.Service
    ( requestFixedExport
    , requestPayrollWorkbookXlsxExportWithDefinition
    ) where

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
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import Data.Either (isRight)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
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
                HourlyBreakdownZip -> requestHourlyZipExport StaffHoursZip rangeStart rangeEnd
                HourlyWageTotalsZip -> requestHourlyZipExport WageTotalsZip rangeStart rangeEnd
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
        expiresAt <- newExportExpiry
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
                expiresAt
                (length includedEntries)
                [ "rowCount" Aeson..= rowCount
                , "workbookVersion" Aeson..= (1 :: Int)
                , "definitionKey" Aeson..= definition.payrollWorkbookDefinitionKey
                , "definitionVersion" Aeson..= definition.payrollWorkbookDefinitionVersion
                , "sheetFamilies" Aeson..= definitionSnapshot
                ]
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
    expiresAt <- newExportExpiry
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
        entryCount
        [ "rowCount" Aeson..= rowCount
        ]

data HourlyZipKind = StaffHoursZip | WageTotalsZip

-- Both formats enforce the same sealed entries and perform the same ordered
-- reads. Wage allocation remains an explicit additional failure boundary.
requestHourlyZipExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    HourlyZipKind -> Day -> Day -> IO (Either Text ExportJob)
requestHourlyZipExport kind rangeStart rangeEnd = do
    entries <- fetchApprovedTimesheetEntries rangeStart rangeEnd
    venueConfig <- fetchVenueConfig
    enforceFinalWageEntries entries >>= \case
        Left failures -> pure (Left (renderWageEntryFailures "Payroll output blocked: " failures))
        Right calculations -> case buildHourlyReportWindow venueConfig entries of
            Left _ -> pure (Left invalidTimesheetTimingExportMessage)
            Right window -> do
                activeShiftTypes <- fetchCurrentVenueActiveShiftTypes
                reportShiftTypes <- fetchReportShiftTypes entries
                shiftLabelsByEntryId <- fetchApprovedEntryShiftLabels entries
                versionManifestsByEntryId <- fetchVersionManifestsForEntries entries
                let columns = buildHourlyShiftTypeColumns activeShiftTypes reportShiftTypes entries shiftLabelsByEntryId
                let versionManifests = List.sort (List.nub (Map.elems versionManifestsByEntryId))
                let persistZip exportKind archiveStem dailySuffix renderDate = do
                        let dates = [rangeStart .. rangeEnd]
                        let exportVersionManifest = collapseVersionManifests versionManifests
                        let fileName = archiveStem <> "-" <> tshow rangeStart <> "-to-" <> tshow rangeEnd <> ".zip"
                        let fileContents = renderTextZipBase64
                                [ (tshow date <> "_" <> fallbackReportDayLabel date 0 <> "_" <> dailySuffix <> ".csv", renderDate date)
                                | date <- dates
                                ]
                        expiresAt <- newExportExpiry
                        persistReadyExportJob
                            (exportJobTypeToText exportKind)
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
                            expiresAt
                            (length entries)
                            [ "fileCount" Aeson..= length dates
                            , "effectiveWindowStartHour" Aeson..= window.hourlyWindowStartHour
                            , "effectiveWindowEndHour" Aeson..= window.hourlyWindowEndHour
                            ]
                case kind of
                    StaffHoursZip ->
                        Right <$> persistZip HourlyBreakdownZip "hourly_staff_hours" "staff_hours"
                            (\date -> renderHourlyBreakdownDateCsv date window columns entries)
                    WageTotalsZip ->
                        case buildHourlyWageCents entries (calculationMap entries calculations) of
                            Left message -> pure (Left ("Hourly wage totals blocked: " <> message))
                            Right wageCents ->
                                Right <$> persistZip HourlyWageTotalsZip "hourly_wage_totals" "wage_totals"
                                    (\date -> renderHourlyWageTotalsDateCsv date window columns wageCents)

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
                expiresAt <- newExportExpiry
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
                    expiresAt
                    (length filteredEntries)
                    [ "rowCount" Aeson..= length records
                    ]
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
        expiresAt <- newExportExpiry
        let exportType = exportJobTypeToText ApprovedTimesheetsCsv
        let initialScope =
                Aeson.object
                    [ "rangeStart" Aeson..= rangeStart
                    , "rangeEnd" Aeson..= rangeEnd
                    , "approvedOnly" Aeson..= True
                    ]
        exportJob <- createPendingExportJob exportType rangeStart rangeEnd initialScope expiresAt

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
        completeExportJob entries exportJob finalScope fileName
            "text/csv; charset=utf-8" "utf8" csvContents exportVersionManifest
            (length entries)
            []

enforceExportEntries :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Either Text ())
enforceExportEntries entries =
    enforceFinalWageEntries entries >>= \case
        Left failures -> pure (Left (renderWageEntryFailures "Payroll output blocked: " failures))
        Right _       -> pure (Right ())

module Application.Helper.Export.Service where

import Application.Helper.Controller
import Application.Helper.Export.Definitions
import Application.Helper.Export.Payloads
import Application.Helper.Export.Persistence
import Application.Helper.Export.ReadModel
import Application.Helper.Export.Render
import Application.Helper.Export.Types
import Application.Helper.Pay (fetchTimesheetPayResultsForEntries,
                               timesheetEntryIdKey)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
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

requestApprovedTimesheetsCsvExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO ExportJob
requestApprovedTimesheetsCsvExport rangeStart rangeEnd = withTransaction do
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
            |> set #destinationMetadata (Aeson.object ["requestedVia" Aeson..= requestAuditSourceChannel])
            |> set #expiresAt expiresAt
            |> createRecord

    entries <- fetchApprovedTimesheetEntries rangeStart rangeEnd
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

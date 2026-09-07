module Application.Helper.Export.Persistence where

import Application.Helper.Controller
import Application.Helper.Export.ReadModel
import Application.Helper.Export.Types
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Time.Calendar (Day)
import Data.Time.Clock (UTCTime, getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude

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
    entries <- fetchApprovedTimesheetEntries rangeStart rangeEnd
    persistReadyExportJobForEntries entries exportType rangeStart rangeEnd finalScope fileName contentType fileEncoding fileContents exportVersionManifest expiresAt auditPayload

persistReadyExportJobForEntries ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    [TimesheetEntry] ->
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
persistReadyExportJobForEntries entries exportType rangeStart rangeEnd finalScope fileName contentType fileEncoding fileContents exportVersionManifest expiresAt auditPayload = do
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
            |> set #destinationMetadata (Aeson.object ["requestedVia" Aeson..= auditSourceChannelText requestAuditSourceChannel])
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

    recordExportJobEntries exportJob entries

    void $ recordCurrentUserAuditEvent
        ExportGeneratedAudit
        "export_jobs"
        (unpackId (get #id exportJob))
        auditPayload

    pure exportJob

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



authorizeExportDownload ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) =>
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
recordExportDownload exportJob = do
    now <- getCurrentTime
    exportJob <-
        exportJob
            |> set #downloadedAt (Just now)
            |> set #downloadedByUserId (Just (unpackId (get #id authenticatedCurrentUser)))
            |> updateRecord

    void $ recordCurrentUserAuditEvent
        ExportDownloadedAudit
        "export_jobs"
        (unpackId (get #id exportJob))
        (Aeson.object
            [ "exportType" Aeson..= exportJob.exportType
            , "generatedFileId" Aeson..= exportJob.generatedFileId
            , "deliveryMethod" Aeson..= exportJob.deliveryMethod
            ]
        )

    pure exportJob

shouldExpireExportJob :: UTCTime -> ExportJob -> Bool
shouldExpireExportJob now exportJob =
    exportJob.status /= exportJobStatusToText ExportExpired
        && exportJob.expiresAt <= now

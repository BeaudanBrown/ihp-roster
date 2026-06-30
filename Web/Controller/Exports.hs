module Web.Controller.Exports where

import Application.Helper.Export
import Application.Helper.LiveResource (LiveMutationResult (..))
import qualified Data.ByteString.Base64 as Base64
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import Network.HTTP.Types.Header (hContentDisposition, hContentType)
import Network.HTTP.Types.Status (status200)
import Network.Wai (responseLBS)
import Web.Controller.Prelude
import Web.Exports.Mutations (recordExportDownloadMutation,
                              requestFixedExportMutation)
import Web.View.Admin.Exports (renderExportsSectionFragment,
                               renderExportsSectionFragmentWithSwap)

respondToAdminExportsSectionMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
respondToAdminExportsSectionMutation =
    if isHtmxRequest
        then do
            currentWeekOffset <- currentReportWeekOffset
            reportWeekSelection <- fetchReportWeekSelection currentWeekOffset
            let defaultRangeStart = reportWeekSelection.weekStart
            let defaultRangeEnd = reportWeekSelection.weekEnd
            exportJobs <- fetchCurrentVenueExportJobs
            setHeader ("HX-Reswap", "none")
            respondHtml (renderExportsSectionFragmentWithSwap (Just "outerHTML") reportWeekSelection defaultRangeStart defaultRangeEnd exportJobs)
        else redirectToPath (pathTo AdminAction <> "#exports")

instance Controller ExportsController where
    beforeAction = do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenue
        ensureProfileCompleted
        ensureAdminRole

    action ExportJobsAction = do
        redirectToPath (pathTo AdminAction <> "#exports")

    action CreateExportJobAction = do
        ensureVenueWritable
        let maybeRangeStart = paramOrNothing @Day "rangeStart"
        let maybeRangeEnd = paramOrNothing @Day "rangeEnd"
        let maybeExportType = paramOrNothing @Text "exportType" >>= parseExportJobType

        case (maybeExportType, maybeRangeStart, maybeRangeEnd) of
            (Just exportType, Just rangeStart, Just rangeEnd) -> do
                requestFixedExportMutation exportType rangeStart rangeEnd >>= \case
                    Left message -> setErrorMessage message
                    Right _ -> do
                        setSuccessMessage "Export generated"
                respondToAdminExportsSectionMutation
            _ -> do
                setErrorMessage "Choose an export type and a valid start and end date."
                respondToAdminExportsSectionMutation

    action DownloadExportJobAction { exportJobId } = do
        let downloadToken = param @UUID "token"
        exportJob <- liveMutationValue <$> (authorizeExportDownload exportJobId downloadToken >>= recordExportDownloadMutation)

        let fileName = Text.replace "\"" "" (fromMaybe "export.csv" exportJob.fileName)
        let contentType = fromMaybe "text/csv; charset=utf-8" exportJob.contentType
        let fileContents =
                case exportJob.fileEncoding of
                    "base64" ->
                        case Base64.decode (encodeUtf8 (fromMaybe "" exportJob.fileContents)) of
                            Left _      -> ""
                            Right bytes -> cs bytes
                    _ -> cs (fromMaybe "" exportJob.fileContents)
        let contentDisposition = "attachment; filename=\"" <> fileName <> "\""

        respondAndExit $
            responseLBS
                status200
                [ (hContentType, cs contentType)
                , (hContentDisposition, cs contentDisposition)
                ]
                fileContents

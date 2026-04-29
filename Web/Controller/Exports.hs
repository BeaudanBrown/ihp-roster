module Web.Controller.Exports where

import Application.Helper.Export
import qualified Data.ByteString.Base64 as Base64
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import Network.HTTP.Types.Header (hContentDisposition, hContentType)
import Network.HTTP.Types.Status (status200)
import Network.Wai (responseLBS)
import Web.Controller.Prelude

instance Controller ExportsController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenue
        ensureProfileCompleted
        ensureAdminRole

    action ExportJobsAction = do
        redirectToPath (pathTo AdminAction <> "#exports")

    action CreateExportJobAction = do
        let maybeRangeStart = paramOrNothing @Day "rangeStart"
        let maybeRangeEnd = paramOrNothing @Day "rangeEnd"
        let maybeExportType = paramOrNothing @Text "exportType" >>= parseExportJobType

        case (maybeExportType, maybeRangeStart, maybeRangeEnd) of
            (Just exportType, Just rangeStart, Just rangeEnd) -> do
                requestFixedExport exportType rangeStart rangeEnd >>= \case
                    Left message -> setErrorMessage message
                    Right _ -> setSuccessMessage "Export generated"
                redirectToPath (pathTo AdminAction <> "#exports")
            _ -> do
                setErrorMessage "Choose an export type and a valid start and end date."
                redirectToPath (pathTo AdminAction <> "#exports")

    action DownloadExportJobAction { exportJobId } = do
        let downloadToken = param @UUID "token"
        exportJob <- authorizeExportDownload exportJobId downloadToken >>= recordExportDownload

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

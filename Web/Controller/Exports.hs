module Web.Controller.Exports where

import Application.Helper.Export
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.Admin.Action as AdminAction
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.Url (appendQueryParams)
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter),
                                errorToast, renderToastOob)
import qualified Data.ByteString.Base64 as Base64
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import Network.HTTP.Types.Header (hContentDisposition, hContentType)
import Network.HTTP.Types.Status (status200)
import Network.Wai (responseLBS)
import Web.Controller.Prelude
import Web.Exports.Mutations (recordExportDownloadMutation,
                              requestFixedExportMutation)

exportDownloadUrl :: ExportJob -> Text
exportDownloadUrl exportJob =
    appendQueryParams
        (pathTo (DownloadExportJobAction exportJob.id))
        [("token", tshow exportJob.downloadToken)]

respondWithExportGenerationError ::
    (?context :: ControllerContext, ?request :: Request) =>
    Text ->
    IO ()
respondWithExportGenerationError message =
    if isHtmxRequest
        then do
            setHeader ("HX-Reswap", "none")
            respondHtml (renderToastOob ToastBottomCenter (errorToast message))
        else do
            setErrorMessage message
            redirectToPath (appendQueryParams (pathTo AdminAction) [("showExports", "true")] <> "#exports")

respondWithGeneratedExportDownload ::
    (?context :: ControllerContext, ?request :: Request) =>
    ExportJob ->
    IO ()
respondWithGeneratedExportDownload exportJob =
    if isHtmxRequest
        then do
            setHeader ("HX-Redirect", cs (exportDownloadUrl exportJob))
            setHeader ("HX-Reswap", "none")
            respondHtml mempty
        else redirectToPath (exportDownloadUrl exportJob)

instance Controller ExportsController where
    beforeAction = bepisBeforeAction BepisAdminVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenue
        ensureProfileCompleted
        ensureAdminRole

    action currentAction@ExportJobsAction = runBepis currentAction BepisExportAction do
        redirectToPath (pathTo AdminAction <> "#exports")

    action currentAction@CreateExportJobAction = runBepis currentAction BepisExportAction do
        ensureVenueWritable
        case AdminAction.parseCreateExportJobActionParams of
            Left errors ->
                respondWithExportGenerationError ("Choose an export type and a valid roster week. " <> surfaceRequestFieldErrorsMessage errors)
            Right fields ->
                case parseExportJobType (surfaceFieldValue @Surface.ExportType fields) of
                    Just exportType ->
                        requestFixedExportMutation exportType (surfaceFieldValue @Surface.RangeStart fields) (surfaceFieldValue @Surface.RangeEnd fields) >>= \case
                            Left message -> respondWithExportGenerationError message
                            Right result -> respondWithGeneratedExportDownload result.liveMutationValue
                    Nothing -> respondWithExportGenerationError "Choose a valid export type and roster week."

    action currentAction@DownloadExportJobAction { exportJobId } = runBepis currentAction BepisExportAction do
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

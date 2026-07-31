module Web.Controller.Exports where

import Application.Helper.Export
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.Admin.Action as AdminAction
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter),
                                errorToast, renderToastOob, successToast)
import qualified Data.ByteString.Base64 as Base64
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import Network.HTTP.Types.Header (hContentDisposition, hContentType)
import Network.HTTP.Types.Status (status200)
import Network.Wai (responseLBS)
import Text.Blaze.Html (Html)
import Web.Controller.Prelude
import Web.Exports.Mutations (recordExportDownloadMutation,
                              requestFixedExportMutation)
import Web.View.Admin.Exports (renderExportsSectionFragment,
                               renderExportsSectionFragmentWithSwap)

respondToAdminExportsSectionMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Html ->
    IO ()
respondToAdminExportsSectionMutation requesterExtras =
    if isHtmxRequest
        then do
            (defaultRangeStart, defaultRangeEnd) <- currentExportDateRange
            exportJobs <- fetchCurrentVenueExportJobs
            setHeader ("HX-Reswap", "none")
            respondHtml (renderExportsSectionFragmentWithSwap (Just "outerHTML") defaultRangeStart defaultRangeEnd exportJobs <> requesterExtras)
        else redirectToPath (pathTo AdminAction <> "#exports")

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
            Left errors -> do
                let message = "Choose an export type and a valid start and end date. " <> surfaceRequestFieldErrorsMessage errors
                if isHtmxRequest
                    then respondToAdminExportsSectionMutation (renderToastOob ToastBottomCenter (errorToast message))
                    else do
                        setErrorMessage message
                        respondToAdminExportsSectionMutation mempty
            Right fields ->
                case parseExportJobType (surfaceFieldValue @Surface.ExportType fields) of
                    Just exportType -> do
                        requestFixedExportMutation exportType (surfaceFieldValue @Surface.RangeStart fields) (surfaceFieldValue @Surface.RangeEnd fields) >>= \case
                            Left message ->
                                if isHtmxRequest
                                    then respondToAdminExportsSectionMutation (renderToastOob ToastBottomCenter (errorToast message))
                                    else do
                                        setErrorMessage message
                                        respondToAdminExportsSectionMutation mempty
                            Right _ ->
                                if isHtmxRequest
                                    then respondToAdminExportsSectionMutation (renderToastOob ToastBottomCenter (successToast "Export generated"))
                                    else do
                                        setSuccessMessage "Export generated"
                                        respondToAdminExportsSectionMutation mempty
                    Nothing -> do
                        let message = "Choose an export type and a valid start and end date."
                        if isHtmxRequest
                            then respondToAdminExportsSectionMutation (renderToastOob ToastBottomCenter (errorToast message))
                            else do
                                setErrorMessage message
                                respondToAdminExportsSectionMutation mempty

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

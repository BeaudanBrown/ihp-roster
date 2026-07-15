module Web.Controller.Exports where

import Application.Helper.Export
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import Application.Helper.FrontendContract.Surface.Request (parseSurfaceActionParams,
                                                            surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
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
            (defaultRangeStart, defaultRangeEnd) <- currentExportDateRange
            exportJobs <- fetchCurrentVenueExportJobs
            setHeader ("HX-Reswap", "none")
            respondHtml (renderExportsSectionFragmentWithSwap (Just "outerHTML") defaultRangeStart defaultRangeEnd exportJobs)
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
        case parseSurfaceActionParams @Surface.AdminExportsSurface @Surface.CreateExportJob of
            Left errors -> do
                setErrorMessage ("Choose an export type and a valid start and end date. " <> surfaceRequestFieldErrorsMessage errors)
                respondToAdminExportsSectionMutation
            Right fields ->
                case parseExportJobType (surfaceFieldValue @Surface.ExportType fields) of
                    Just exportType -> do
                        requestFixedExportMutation exportType (surfaceFieldValue @Surface.RangeStart fields) (surfaceFieldValue @Surface.RangeEnd fields) >>= \case
                            Left message -> setErrorMessage message
                            Right _ -> setSuccessMessage "Export generated"
                        respondToAdminExportsSectionMutation
                    Nothing -> do
                        setErrorMessage "Choose an export type and a valid start and end date."
                        respondToAdminExportsSectionMutation

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

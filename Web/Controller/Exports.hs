module Web.Controller.Exports where

import Application.Helper.Export
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.Admin.Action as AdminAction
import Application.Helper.FrontendContract.Surface.Admin.Live (adminExportsLiveScope)
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.Url (appendQueryParams)
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter),
                                errorToast, renderToastOob, successToast)
import qualified Data.ByteString.Base64 as Base64
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import Network.HTTP.Types.Header (hContentDisposition, hContentType)
import Network.HTTP.Types.Status (status200)
import Network.Wai (responseLBS)
import qualified Web.Admin.FrontendSurface as AdminSurface
import Web.Controller.Prelude
import Web.Exports.Mutations (createPayrollWorkbookConfigurationMutation,
                              deletePayrollWorkbookConfigurationMutation,
                              recordExportDownloadMutation,
                              requestFixedExportMutation,
                              requestFixedExportWithPayrollWorkbookDefinitionMutation)

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

payrollWorkbookConfigurationErrorMessage :: PayrollWorkbookConfigurationError -> Text
payrollWorkbookConfigurationErrorMessage = \case
    PayrollWorkbookConfigurationAccessDenied -> "You do not have access to Payroll Workbook configurations."
    PayrollWorkbookConfigurationInvalidName message -> message
    PayrollWorkbookConfigurationInvalidDefinition message -> message
    PayrollWorkbookConfigurationNameConflict name -> "A Payroll Workbook configuration named “" <> name <> "” already exists."
    PayrollWorkbookConfigurationNotFound -> "That Payroll Workbook configuration no longer exists."
    PayrollWorkbookConfigurationStoredDefinitionInvalid _ -> "That Payroll Workbook configuration is no longer valid."

respondWithPayrollWorkbookConfigurationError ::
    (?context :: ControllerContext, ?request :: Request) =>
    Day ->
    Text ->
    IO ()
respondWithPayrollWorkbookConfigurationError anchorDate message =
    if isHtmxRequest
        then do
            setHeader ("HX-Reswap", "none")
            respondHtml (renderToastOob ToastBottomCenter (errorToast message))
        else do
            setErrorMessage message
            redirectToPath (adminExportsPath anchorDate)

respondWithPayrollWorkbookConfigurationMutation ::
    (?context :: ControllerContext, ?request :: Request) =>
    Day ->
    Text ->
    LiveMutationResult value ->
    IO ()
respondWithPayrollWorkbookConfigurationMutation anchorDate message mutationResult =
    if isHtmxRequest
        then do
            setHeader ("HX-Reswap", "none")
            setActorLiveResourcesRefresh
                (adminExportsLiveScope (unpackId currentVenueId))
                mutationResult.liveMutationTouchedResources
                [AdminSurface.adminExportsFragmentForWindow anchorDate]
            respondHtml (renderToastOob ToastBottomCenter (successToast message))
        else do
            setSuccessMessage message
            redirectToPath (adminExportsPath anchorDate)

adminExportsPath :: Day -> Text
adminExportsPath anchorDate =
    appendQueryParams
        (pathTo AdminAction)
        [ ("showExports", "true")
        , ("anchorDate", tshow anchorDate)
        ]
        <> "#exports"

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
            Right fields -> do
                let exportType = surfaceFieldValue @Surface.ExportType fields
                let rangeStart = surfaceFieldValue @Surface.RangeStart fields
                let rangeEnd = surfaceFieldValue @Surface.RangeEnd fields
                let maybeConfigurationId = Id <$> surfaceFieldValue @Surface.PayrollWorkbookConfigurationId fields
                case (exportType, maybeConfigurationId) of
                    (PayrollWorkbookXlsx, Just configurationId) ->
                        fetchSavedPayrollWorkbookConfiguration configurationId >>= \case
                            Left configurationError -> respondWithExportGenerationError (payrollWorkbookConfigurationErrorMessage configurationError)
                            Right configuration ->
                                requestFixedExportWithPayrollWorkbookDefinitionMutation configuration.savedPayrollWorkbookConfigurationDefinition rangeStart rangeEnd >>= \case
                                    Left message -> respondWithExportGenerationError message
                                    Right result -> respondWithGeneratedExportDownload result.liveMutationValue
                    (PayrollWorkbookXlsx, Nothing) ->
                        requestFixedExportMutation exportType rangeStart rangeEnd >>= \case
                            Left message -> respondWithExportGenerationError message
                            Right result -> respondWithGeneratedExportDownload result.liveMutationValue
                    (_, Just _) -> respondWithExportGenerationError "Saved Payroll Workbook configurations can only generate Payroll Workbooks."
                    (_, Nothing) ->
                        requestFixedExportMutation exportType rangeStart rangeEnd >>= \case
                            Left message -> respondWithExportGenerationError message
                            Right result -> respondWithGeneratedExportDownload result.liveMutationValue

    action currentAction@CreatePayrollWorkbookConfigurationAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        case AdminAction.parseCreatePayrollWorkbookConfigurationActionParams of
            Left errors -> do
                fallbackSelection <- currentExportWeekSelection
                respondWithPayrollWorkbookConfigurationError
                    fallbackSelection.weekStart
                    ("Check the saved configuration fields. " <> surfaceRequestFieldErrorsMessage errors)
            Right fields -> do
                let anchorDate = surfaceFieldValue @Surface.RangeStart fields
                let familyKeys =
                        filter (not . Text.null) $
                            catMaybes
                                [ Just (surfaceFieldValue @Surface.PayrollWorkbookSheetFamily1 fields)
                                , surfaceFieldValue @Surface.PayrollWorkbookSheetFamily2 fields
                                , surfaceFieldValue @Surface.PayrollWorkbookSheetFamily3 fields
                                , surfaceFieldValue @Surface.PayrollWorkbookSheetFamily4 fields
                                , surfaceFieldValue @Surface.PayrollWorkbookSheetFamily5 fields
                                ]
                let input =
                        NewPayrollWorkbookConfiguration
                            { newPayrollWorkbookConfigurationName = surfaceFieldValue @Surface.PayrollWorkbookConfigurationName fields
                            , newPayrollWorkbookConfigurationDefinitionVersion = 1
                            , newPayrollWorkbookConfigurationFamilyKeys = familyKeys
                            }
                createPayrollWorkbookConfigurationMutation input >>= \case
                    Left configurationError -> respondWithPayrollWorkbookConfigurationError anchorDate (payrollWorkbookConfigurationErrorMessage configurationError)
                    Right result -> respondWithPayrollWorkbookConfigurationMutation anchorDate "Payroll Workbook configuration saved." result

    action currentAction@DeletePayrollWorkbookConfigurationAction { payrollWorkbookConfigurationId, anchorDate = anchorDateParam } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        deletePayrollWorkbookConfigurationMutation payrollWorkbookConfigurationId >>= \case
            Left configurationError -> respondWithPayrollWorkbookConfigurationError anchorDate (payrollWorkbookConfigurationErrorMessage configurationError)
            Right result -> respondWithPayrollWorkbookConfigurationMutation anchorDate "Payroll Workbook configuration deleted." result

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

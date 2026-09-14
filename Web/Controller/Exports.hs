module Web.Controller.Exports where

import Application.Helper.Export
import qualified Application.Helper.FrontendContract.AppShell as AppShell
import Application.Helper.FrontendContract.AppShell.Request (parseAppShellActionParams)
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.Admin.Action as AdminAction
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.Url (appendQueryParams)
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter),
                                errorToast, renderToastOob)
import qualified Data.ByteString.Base64 as Base64
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import Network.HTTP.Types.Header (hContentDisposition, hContentType)
import Network.HTTP.Types.Status (status200)
import Network.Wai (responseLBS)
import Web.Controller.Prelude
import Web.Exports.Mutations (deletePayrollWorkbookConfigurationMutation,
                              recordExportDownloadMutation,
                              requestFixedExportMutation,
                              requestFixedExportWithPayrollWorkbookDefinitionMutation)
import Web.Exports.Responses
import Web.Exports.WorkbookConfigurations (createSavedWorkbookFromRequest,
                                          editSavedWorkbookFromRequest)
import Web.View.Admin.PayrollWorkbookConfigurationDialog

exportDownloadUrl :: ExportJob -> Text
exportDownloadUrl exportJob =
    appendQueryParams
        (pathTo (DownloadExportJobAction exportJob.id))
        [("token", tshow exportJob.downloadToken)]

respondWithExportGenerationError ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Text ->
    IO ResponseReceived
respondWithExportGenerationError message =
    if isHtmxRequest
        then do
            setHeader ("HX-Reswap", "none")
            respondHtml (renderToastOob ToastBottomCenter (errorToast message))
        else do
            setErrorMessage message
            redirectToPath (appendQueryParams (pathTo AdminAction) [("showExports", "true")] <> "#exports")

respondWithGeneratedExportDownload ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    ExportJob ->
    IO ResponseReceived
respondWithGeneratedExportDownload exportJob =
    if isHtmxRequest
        then do
            setHeader ("HX-Redirect", cs (exportDownloadUrl exportJob))
            setHeader ("HX-Reswap", "none")
            respondHtml mempty
        else redirectToPath (exportDownloadUrl exportJob)

data PayrollWorkbookConfigurationDraftOperation
    = AddDraftSheet
    | RemoveDraftSheet
    | MoveDraftSheetUp
    | MoveDraftSheetDown

respondWithPayrollWorkbookConfigurationDraftControl ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    PayrollWorkbookConfigurationDraftOperation ->
    Day ->
    Text ->
    [Text] ->
    Int ->
    Maybe UUID ->
    Text ->
    IO ResponseReceived
respondWithPayrollWorkbookConfigurationDraftControl operation anchorDate name familyKeys revision maybeConfigurationId targetFamilyKey =
    case (mapM payrollWorkbookSheetFamilyFromText familyKeys, payrollWorkbookSheetFamilyFromText targetFamilyKey) of
        (Left message, _) -> respondWithDraftError newPayrollWorkbookConfigurationDraft message
        (_, Left message) -> respondWithDraftError newPayrollWorkbookConfigurationDraft message
        (Right families, Right targetFamily)
            | length families /= length (List.nub families) -> respondWithDraftError (draftWith families) "Sheet families cannot be duplicated."
            | otherwise -> respondWithDraft (draftWith (applyDraftOperation operation targetFamily families))
  where
    draftWith families =
        PayrollWorkbookConfigurationDraft
            { payrollWorkbookConfigurationDraftId = Id <$> maybeConfigurationId
            , payrollWorkbookConfigurationDraftName = name
            , payrollWorkbookConfigurationDraftFamilies = families
            , payrollWorkbookConfigurationDraftRevision = revision
            , payrollWorkbookConfigurationDraftError = Nothing
            }
    respondWithDraft draft =
        if isHtmxRequest
            then respondHtml (renderPayrollWorkbookConfigurationDialog anchorDate draft)
            else redirectToPath (adminExportsPath anchorDate)
    respondWithDraftError draft message =
        respondWithDraft draft { payrollWorkbookConfigurationDraftError = Just message }

applyDraftOperation :: PayrollWorkbookConfigurationDraftOperation -> PayrollWorkbookSheetFamily -> [PayrollWorkbookSheetFamily] -> [PayrollWorkbookSheetFamily]
applyDraftOperation operation target families =
    case operation of
        AddDraftSheet
            | target `elem` families -> families
            | otherwise -> families <> [target]
        RemoveDraftSheet -> filter (/= target) families
        MoveDraftSheetUp -> moveDraftSheet (-1) target families
        MoveDraftSheetDown -> moveDraftSheet 1 target families

moveDraftSheet :: Int -> PayrollWorkbookSheetFamily -> [PayrollWorkbookSheetFamily] -> [PayrollWorkbookSheetFamily]
moveDraftSheet offset target families =
    case List.elemIndex target families of
        Nothing -> families
        Just sourceIndex
            | destinationIndex < 0 || destinationIndex >= length families -> families
            | otherwise -> swapAt sourceIndex destinationIndex families
          where
            destinationIndex = sourceIndex + offset

swapAt :: Int -> Int -> [value] -> [value]
swapAt leftIndex rightIndex values =
    case (safeIndex leftIndex values, safeIndex rightIndex values) of
        (Just leftValue, Just rightValue) ->
            zipWith (replace leftValue rightValue) [0 :: Int ..] values
        _ -> values
  where
    safeIndex index _ | index < 0 = Nothing
    safeIndex index list = listToMaybe (drop index list)
    replace leftValue rightValue index value
        | index == leftIndex = rightValue
        | index == rightIndex = leftValue
        | otherwise = value

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
                    (_, Just _) -> respondWithExportGenerationError "Payroll Workbook export configurations can only generate Payroll Workbooks."
                    (_, Nothing) ->
                        requestFixedExportMutation exportType rangeStart rangeEnd >>= \case
                            Left message -> respondWithExportGenerationError message
                            Right result -> respondWithGeneratedExportDownload result.liveMutationValue

    action currentAction@NewPayrollWorkbookConfigurationAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFormAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        respondWithNewWorkbookEditor anchorDate

    action currentAction@EditPayrollWorkbookConfigurationAction { payrollWorkbookConfigurationId, anchorDate = anchorDateParam } = runBepis currentAction BepisFormAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        fetchSavedPayrollWorkbookConfiguration payrollWorkbookConfigurationId >>= respondWithSavedWorkbookEditor anchorDate

    action currentAction@CreatePayrollWorkbookConfigurationAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        createSavedWorkbookFromRequest >>= respondWithWorkbookEditorOutcome

    action currentAction@UpdatePayrollWorkbookConfigurationAction { payrollWorkbookConfigurationId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        editSavedWorkbookFromRequest payrollWorkbookConfigurationId >>= respondWithWorkbookEditorOutcome

    action currentAction@AddPayrollWorkbookConfigurationSheetDraftAction = runBepis currentAction BepisFormAction do
        case parseAppShellActionParams @AppShell.AddPayrollWorkbookConfigurationSheetOverlay of
            Left errors -> do
                fallbackSelection <- currentExportWeekSelection
                respondWithPayrollWorkbookConfigurationEditorError fallbackSelection.weekStart newPayrollWorkbookConfigurationDraft (surfaceRequestFieldErrorsMessage errors)
            Right fields ->
                respondWithPayrollWorkbookConfigurationDraftControl
                    AddDraftSheet
                    (surfaceFieldValue @AppShell.ExportAnchorDateField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookConfigurationNameField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookSheetFamiliesField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookConfigurationRevisionField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookConfigurationIdField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookConfigurationSheetField fields)

    action currentAction@RemovePayrollWorkbookConfigurationSheetDraftAction = runBepis currentAction BepisFormAction do
        case parseAppShellActionParams @AppShell.RemovePayrollWorkbookConfigurationSheetOverlay of
            Left errors -> do
                fallbackSelection <- currentExportWeekSelection
                respondWithPayrollWorkbookConfigurationEditorError fallbackSelection.weekStart newPayrollWorkbookConfigurationDraft (surfaceRequestFieldErrorsMessage errors)
            Right fields ->
                respondWithPayrollWorkbookConfigurationDraftControl
                    RemoveDraftSheet
                    (surfaceFieldValue @AppShell.ExportAnchorDateField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookConfigurationNameField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookSheetFamiliesField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookConfigurationRevisionField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookConfigurationIdField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookConfigurationSheetField fields)

    action currentAction@MovePayrollWorkbookConfigurationSheetUpDraftAction = runBepis currentAction BepisFormAction do
        case parseAppShellActionParams @AppShell.MovePayrollWorkbookConfigurationSheetUpOverlay of
            Left errors -> do
                fallbackSelection <- currentExportWeekSelection
                respondWithPayrollWorkbookConfigurationEditorError fallbackSelection.weekStart newPayrollWorkbookConfigurationDraft (surfaceRequestFieldErrorsMessage errors)
            Right fields ->
                respondWithPayrollWorkbookConfigurationDraftControl
                    MoveDraftSheetUp
                    (surfaceFieldValue @AppShell.ExportAnchorDateField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookConfigurationNameField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookSheetFamiliesField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookConfigurationRevisionField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookConfigurationIdField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookConfigurationSheetField fields)

    action currentAction@MovePayrollWorkbookConfigurationSheetDownDraftAction = runBepis currentAction BepisFormAction do
        case parseAppShellActionParams @AppShell.MovePayrollWorkbookConfigurationSheetDownOverlay of
            Left errors -> do
                fallbackSelection <- currentExportWeekSelection
                respondWithPayrollWorkbookConfigurationEditorError fallbackSelection.weekStart newPayrollWorkbookConfigurationDraft (surfaceRequestFieldErrorsMessage errors)
            Right fields ->
                respondWithPayrollWorkbookConfigurationDraftControl
                    MoveDraftSheetDown
                    (surfaceFieldValue @AppShell.ExportAnchorDateField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookConfigurationNameField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookSheetFamiliesField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookConfigurationRevisionField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookConfigurationIdField fields)
                    (surfaceFieldValue @AppShell.PayrollWorkbookConfigurationSheetField fields)

    action currentAction@ConfirmDeletePayrollWorkbookConfigurationAction { payrollWorkbookConfigurationId, anchorDate = anchorDateParam } = runBepis currentAction BepisFormAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        fetchSavedPayrollWorkbookConfiguration payrollWorkbookConfigurationId >>= respondWithWorkbookDeleteConfirmation anchorDate

    action currentAction@DeletePayrollWorkbookConfigurationAction { payrollWorkbookConfigurationId, anchorDate = anchorDateParam } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        deletePayrollWorkbookConfigurationMutation payrollWorkbookConfigurationId >>= respondWithWorkbookDeletion anchorDate

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

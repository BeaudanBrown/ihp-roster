{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

-- | Saved Workbook feedback and dialog completion. Passive publication remains
-- exclusively with the durable mutation; these responses only refresh the actor.
module Web.Exports.Responses
    ( adminExportsPath
    , payrollWorkbookConfigurationErrorMessage
    , respondWithNewWorkbookEditor
    , respondWithSavedWorkbookEditor
    , respondWithWorkbookDeleteConfirmation
    , respondWithWorkbookDeletion
    , respondWithWorkbookEditorOutcome
    , respondWithPayrollWorkbookConfigurationEditorError
    ) where

import Application.Helper.Export
import Application.Helper.FrontendContract.Surface.Admin.Live (adminExportsLiveScope)
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.Url (appendQueryParams)
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter),
                                errorToast, renderDialogOverlayClearOob,
                                renderToastOob, successToast)
import qualified Web.Admin.FrontendSurface as AdminSurface
import Web.Controller.Prelude
import Web.Exports.WorkbookConfigurations (WorkbookEditorOutcome (..))
import Web.View.Admin.PayrollWorkbookConfigurationDialog

respondWithWorkbookEditorOutcome ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    WorkbookEditorOutcome ->
    IO ResponseReceived
respondWithWorkbookEditorOutcome = \case
    WorkbookEditorInvalidFields anchorDate draft errors ->
        respondWithPayrollWorkbookConfigurationEditorError anchorDate draft ("Check the export fields. " <> surfaceRequestFieldErrorsMessage errors)
    WorkbookEditorRejected anchorDate draft configurationError ->
        respondWithPayrollWorkbookConfigurationEditorError anchorDate draft (payrollWorkbookConfigurationErrorMessage configurationError)
    WorkbookCreated anchorDate result ->
        respondWithPayrollWorkbookConfigurationMutation anchorDate "Payroll Workbook export saved." result
    WorkbookUpdated anchorDate result ->
        respondWithPayrollWorkbookConfigurationMutation anchorDate "Payroll Workbook export updated." result

respondWithNewWorkbookEditor ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Day ->
    IO ResponseReceived
respondWithNewWorkbookEditor anchorDate =
    respondWithWorkbookEditor anchorDate newPayrollWorkbookConfigurationDraft

respondWithSavedWorkbookEditor ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Day ->
    Either PayrollWorkbookConfigurationError SavedPayrollWorkbookConfiguration ->
    IO ResponseReceived
respondWithSavedWorkbookEditor anchorDate = \case
    Left configurationError -> respondWithPayrollWorkbookConfigurationError anchorDate (payrollWorkbookConfigurationErrorMessage configurationError)
    Right configuration -> respondWithWorkbookEditor anchorDate (savedPayrollWorkbookConfigurationDraft configuration)

respondWithWorkbookEditor ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Day ->
    PayrollWorkbookConfigurationDraft ->
    IO ResponseReceived
respondWithWorkbookEditor anchorDate draft =
    if isHtmxRequest
        then respondHtml (renderPayrollWorkbookConfigurationDialog anchorDate draft)
        else redirectToPath (adminExportsPath anchorDate)

respondWithWorkbookDeleteConfirmation ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Day ->
    Either PayrollWorkbookConfigurationError SavedPayrollWorkbookConfiguration ->
    IO ResponseReceived
respondWithWorkbookDeleteConfirmation anchorDate = \case
    Left configurationError -> respondWithPayrollWorkbookConfigurationError anchorDate (payrollWorkbookConfigurationErrorMessage configurationError)
    Right configuration ->
        if isHtmxRequest
            then respondHtml (renderPayrollWorkbookConfigurationDeleteDialog anchorDate configuration)
            else redirectToPath (adminExportsPath anchorDate)

respondWithWorkbookDeletion ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Day ->
    Either PayrollWorkbookConfigurationError (LiveMutationResult ()) ->
    IO ResponseReceived
respondWithWorkbookDeletion anchorDate = \case
    Left configurationError -> respondWithPayrollWorkbookConfigurationError anchorDate (payrollWorkbookConfigurationErrorMessage configurationError)
    Right result -> respondWithPayrollWorkbookConfigurationMutation anchorDate "Payroll Workbook export deleted." result

payrollWorkbookConfigurationErrorMessage :: PayrollWorkbookConfigurationError -> Text
payrollWorkbookConfigurationErrorMessage = \case
    PayrollWorkbookConfigurationAccessDenied -> "You do not have access to Payroll Workbook configurations."
    PayrollWorkbookConfigurationInvalidName message -> message
    PayrollWorkbookConfigurationInvalidDefinition message -> message
    PayrollWorkbookConfigurationNameConflict name -> "A Payroll Workbook configuration named “" <> name <> "” already exists."
    PayrollWorkbookConfigurationNotFound -> "That Payroll Workbook configuration no longer exists."
    PayrollWorkbookConfigurationStale -> "This export changed after you opened it. Close the editor and try again."
    PayrollWorkbookConfigurationStoredDefinitionInvalid _ -> "That Payroll Workbook configuration is no longer valid."

respondWithPayrollWorkbookConfigurationError ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Day ->
    Text ->
    IO ResponseReceived
respondWithPayrollWorkbookConfigurationError anchorDate message =
    if isHtmxRequest
        then do
            setHeader ("HX-Reswap", "none")
            respondHtml (renderToastOob ToastBottomCenter (errorToast message))
        else do
            setErrorMessage message
            redirectToPath (adminExportsPath anchorDate)

respondWithPayrollWorkbookConfigurationMutation ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Day ->
    Text ->
    LiveMutationResult value ->
    IO ResponseReceived
respondWithPayrollWorkbookConfigurationMutation anchorDate message mutationResult =
    if isHtmxRequest
        then do
            setHeader ("HX-Reswap", "none")
            setActorLiveResourcesRefresh
                (adminExportsLiveScope (unpackId currentVenueId))
                mutationResult.liveMutationTouchedResources
                [AdminSurface.adminExportsFragmentForWindow anchorDate]
            respondHtml (renderDialogOverlayClearOob <> renderToastOob ToastBottomCenter (successToast message))
        else do
            setSuccessMessage message
            redirectToPath (adminExportsPath anchorDate)

respondWithPayrollWorkbookConfigurationEditorError ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Day ->
    PayrollWorkbookConfigurationDraft ->
    Text ->
    IO ResponseReceived
respondWithPayrollWorkbookConfigurationEditorError anchorDate draft message =
    if isHtmxRequest
        then respondHtml (renderPayrollWorkbookConfigurationDialog anchorDate draft { payrollWorkbookConfigurationDraftError = Just message })
        else do
            setErrorMessage message
            redirectToPath (adminExportsPath anchorDate)

adminExportsPath :: Day -> Text
adminExportsPath anchorDate =
    appendQueryParams
        (pathTo AdminAction)
        [ ("showExports", "true")
        , ("anchorDate", tshow anchorDate)
        ]
        <> "#exports"

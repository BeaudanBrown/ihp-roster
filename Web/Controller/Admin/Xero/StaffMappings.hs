module Web.Controller.Admin.Xero.StaffMappings
    ( applyXeroStaffMappingAction
    , openXeroStaffMappingsAction
    , showXeroStaffMappingsWaitFragmentAction
    ) where

import Application.Async.Queue (EnqueueAppJobResult (..), activeAppJobStatuses)
import Application.Helper.FrontendContract.AppShell (ApplyXeroStaffMappingOverlay,
                                                     OpenXeroStaffMappingsOverlay,
                                                     StaffIdField,
                                                     XeroEmployeeSelectionField)
import Application.Helper.FrontendContract.AppShell.Request (parseAppShellActionParams)
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter),
                                renderToastOverlayHostOob)
import Application.Helper.XeroAdminTypes
import Application.Xero.Admin.ReadModel
import Application.Xero.ReferenceSyncJob (requestXeroReferenceSyncCategories)
import Application.Xero.StaffMappings (applyXeroStaffMappingSelection)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Set as Set
import Generated.Types
import IHP.Job.Types
import Web.Controller.Admin.Xero.Responses
import Web.Controller.Prelude
import Web.View.Admin.Xero.StaffMappingDialog

openXeroStaffMappingsAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ResponseReceived
openXeroStaffMappingsAction =
    case parseAppShellActionParams @OpenXeroStaffMappingsOverlay of
        Left errors -> respondWithStaffMappingsError (surfaceRequestFieldErrorsMessage errors)
        Right _ ->
            fetchCurrentVenueXeroConnection >>= \case
                Just connection | connection.connectionStatus == "active" -> do
                    request <- requestXeroReferenceSyncCategories (Just currentUser.id) connection (Set.singleton XeroStaff)
                    respondToStaffReferenceRequest connection (jobFromRequest request)
                _ -> respondWithStaffMappingsError "Connect Xero before managing staff mappings."

showXeroStaffMappingsWaitFragmentAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id AppJob ->
    IO ResponseReceived
showXeroStaffMappingsWaitFragmentAction jobId = do
    maybeJob <-
        query @AppJob
            |> filterWhere (#id, jobId)
            |> filterWhere (#venueId, Just (unpackId currentVenueId))
            |> filterWhere (#jobKind, "xero_reference_sync" :: Text)
            |> fetchOneOrNothing
    case maybeJob of
        Nothing -> respondWithStaffMappingsRefreshFailure "Xero staff refresh could not be found. Try opening Staff mappings again."
        Just job ->
            fetchCurrentVenueXeroConnection >>= \case
                Just connection | job.relatedId == Just (unpackId connection.id) -> respondToStaffReferenceRequest connection job
                _ -> respondWithStaffMappingsRefreshFailure "The Xero connection changed while staff were refreshing. Open Staff mappings again."

applyXeroStaffMappingAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ResponseReceived
applyXeroStaffMappingAction =
    case parseAppShellActionParams @ApplyXeroStaffMappingOverlay of
        Left errors -> respondWithCurrentStaffMappingsError (surfaceRequestFieldErrorsMessage errors)
        Right fields ->
            fetchCurrentVenueXeroConnection >>= \case
                Just connection | connection.connectionStatus == "active" -> do
                    let staffId = Id (surfaceFieldValue @StaffIdField fields)
                        selection = surfaceFieldValue @XeroEmployeeSelectionField fields
                    applyXeroStaffMappingSelection currentVenueId currentUser.id connection staffId selection >>= \case
                        Left message -> respondWithCurrentStaffMappingsError message
                        Right _ -> loadXeroStaffMappingsView connection >>= respondHtml . renderXeroStaffMappingsDialog
                _ -> respondWithStaffMappingsError "Connect Xero before managing staff mappings."

jobFromRequest :: EnqueueAppJobResult -> AppJob
jobFromRequest = \case
    EnqueuedAppJob job -> job
    ExistingActiveAppJob job -> job

respondToStaffReferenceRequest ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    AppJob ->
    IO ResponseReceived
respondToStaffReferenceRequest connection job = do
    staffReferenceReady <- xeroStaffReferenceReadySince connection job.createdAt
    if staffReferenceReady
        then loadXeroStaffMappingsView connection >>= respondHtml . renderXeroStaffMappingsDialog
        else if job.status `elem` activeAppJobStatuses
            then respondHtml (renderXeroStaffMappingsWaitingDialog (unpackId currentVenueId) job.id)
            else if referenceSyncRetryScheduled job.result
                then do
                    maybeContinuation <- fetchActiveConnectionReferenceJob connection
                    case maybeContinuation of
                        Just _ -> respondHtml (renderXeroStaffMappingsWaitingDialog (unpackId currentVenueId) job.id)
                        Nothing -> respondWithStaffMappingsRefreshFailure (referenceSyncFailureMessage job)
                else respondWithStaffMappingsRefreshFailure (referenceSyncFailureMessage job)

xeroStaffReferenceReadySince ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    UTCTime ->
    IO Bool
xeroStaffReferenceReadySince connection requestedAt = do
    maybeState <-
        query @XeroReferenceSyncCategoryState
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#category, XeroStaff)
            |> fetchOneOrNothing
    pure (maybe False ((>= requestedAt) . (.lastSuccessAt)) maybeState)

fetchActiveConnectionReferenceJob ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    IO (Maybe AppJob)
fetchActiveConnectionReferenceJob connection =
    query @AppJob
        |> filterWhere (#jobKind, "xero_reference_sync" :: Text)
        |> filterWhere (#relatedId, Just (unpackId connection.id))
        |> filterWhereIn (#status, activeAppJobStatuses)
        |> orderByDesc #createdAt
        |> fetchOneOrNothing

referenceSyncRetryScheduled :: Aeson.Value -> Bool
referenceSyncRetryScheduled =
    fromMaybe False . AesonTypes.parseMaybe (Aeson.withObject "Xero reference retry result" (\object -> (== ("retry_scheduled" :: Text)) <$> object Aeson..: "status"))

referenceSyncFailureMessage :: AppJob -> Text
referenceSyncFailureMessage job =
    fromMaybe "Xero staff could not be refreshed. Try again." job.lastError

loadXeroStaffMappingsView ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    XeroConnection ->
    IO XeroStaffMappingsView
loadXeroStaffMappingsView connection = do
    staffMappingsRows <- fetchCurrentVenueXeroStaffManagementRows connection
    staffMappingsEmployees <- fetchCurrentVenueXeroEmployees (Just connection)
    pure XeroStaffMappingsView { staffMappingsConnection = connection, .. }

respondWithCurrentStaffMappingsError ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO ResponseReceived
respondWithCurrentStaffMappingsError message =
    fetchCurrentVenueXeroConnection >>= \case
        Just connection -> do
            view <- loadXeroStaffMappingsView connection
            respondHtml $
                renderXeroStaffMappingsDialog view
                    <> renderToastOverlayHostOob ToastBottomCenter [xeroErrorToast message]
        Nothing -> respondWithStaffMappingsError message

respondWithStaffMappingsError ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Text ->
    IO ResponseReceived
respondWithStaffMappingsError message = do
    setHeader ("HX-Reswap", "none")
    respondHtml (renderToastOverlayHostOob ToastBottomCenter [xeroErrorToast message])

respondWithStaffMappingsRefreshFailure ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Text ->
    IO ResponseReceived
respondWithStaffMappingsRefreshFailure message =
    respondWithXeroTimesheetMutationAndCloseDialog (Just (xeroErrorToast message))

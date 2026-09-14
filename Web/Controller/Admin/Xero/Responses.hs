module Web.Controller.Admin.Xero.Responses
    ( currentUserCanManageXeroIntegration
    , fetchCurrentVenueXeroAdminSectionData
    , requireCurrentVenueOwnerForXero
    , respondWithXeroSectionActorInvalidationAndToast
    , respondWithXeroSectionFragment
    , respondWithXeroReferenceSyncFragment
    , respondWithXeroToast
    , respondWithXeroTimesheetMutationAndCloseDialog
    , xeroErrorToast
    , xeroSuccessToast
    ) where

import Application.Helper.FrontendContract.Surface.Admin.Live (adminXeroLiveScope)
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh)
import Application.Helper.Profiling
import Application.Helper.SurfaceResource (SurfaceResourceValue)
import Application.Helper.View (ToastOverlayConfig,
                                ToastOverlayPosition (ToastBottomCenter),
                                errorToast, renderDialogOverlayClearOob,
                                renderToastOverlayHostOob, successToast)
import Application.Helper.XeroAdminTypes
import Application.Xero.Admin.ReadModel hiding
                                        (fetchCurrentVenueXeroAdminSectionData)
import qualified Application.Xero.Admin.ReadModel as XeroReadModel
import qualified Data.Set as Set
import qualified Web.Admin.FrontendSurface as AdminSurface
import Web.Controller.Prelude
import Web.View.Admin.Xero

respondWithXeroSectionFragment ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ResponseReceived
respondWithXeroSectionFragment = do
    xeroSectionData <- fetchCurrentVenueXeroAdminSectionData
    fragmentHtml <- profileActionSpan "admin.xero.fragment.render" do
        pure (renderXeroSectionFragment xeroSectionData)
    respondHtmlProfiled fragmentHtml

respondWithXeroReferenceSyncFragment ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ResponseReceived
respondWithXeroReferenceSyncFragment = do
    diagnostics <- profileActionSpan "admin.xero.reference_sync_fragment.fetch" $
        fetchCurrentVenueXeroReferenceSyncDiagnostics currentUserIsUnimpersonatedSuperAdmin
    respondHtmlProfiled (renderXeroReferenceSyncFragment diagnostics)

fetchCurrentVenueXeroAdminSectionData ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO XeroAdminSectionData
fetchCurrentVenueXeroAdminSectionData =
    XeroReadModel.fetchCurrentVenueXeroAdminSectionData currentUserCanManageXeroIntegration

respondWithXeroSectionActorInvalidationAndToast ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Set.Set SurfaceResourceValue ->
    Maybe ToastOverlayConfig ->
    IO ResponseReceived
respondWithXeroSectionActorInvalidationAndToast touchedResources maybeToast = do
    setActorLiveResourcesRefresh
        (adminXeroLiveScope (unpackId currentVenueId))
        touchedResources
        [AdminSurface.adminXeroShellFragment, AdminSurface.adminXeroReferenceSyncFragment]
    respondWithXeroToast maybeToast

respondWithXeroToast ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Maybe ToastOverlayConfig ->
    IO ResponseReceived
respondWithXeroToast maybeToast =
    respondHtmlProfiled $
        maybe mempty (renderToastOverlayHostOob ToastBottomCenter . pure) maybeToast

respondWithXeroTimesheetMutationAndCloseDialog ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Maybe ToastOverlayConfig ->
    IO ResponseReceived
respondWithXeroTimesheetMutationAndCloseDialog maybeToast =
    respondHtmlProfiled $
        mconcat
            [ renderDialogOverlayClearOob
            , maybe mempty (renderToastOverlayHostOob ToastBottomCenter . pure) maybeToast
            ]

xeroSuccessToast :: Text -> ToastOverlayConfig
xeroSuccessToast = successToast

xeroErrorToast :: Text -> ToastOverlayConfig
xeroErrorToast = errorToast

currentUserCanManageXeroIntegration :: (?context :: ControllerContext) => Bool
currentUserCanManageXeroIntegration = hasRole VenueOwner

requireCurrentVenueOwnerForXero :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => IO value -> IO value
requireCurrentVenueOwnerForXero action =
    if currentUserCanManageXeroIntegration
        then action
        else do
            setErrorMessage "Only the venue owner or a super admin can manage Xero for this venue."
            earlyReturn (redirectToPath permissionDeniedFallbackPath)

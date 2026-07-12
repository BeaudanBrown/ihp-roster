module Web.Controller.Admin.Xero.Responses
    ( currentUserCanManageXeroIntegration
    , fetchCurrentVenueXeroAdminSectionData
    , requireCurrentVenueOwnerForXero
    , respondWithXeroSectionActorInvalidationAndToast
    , respondWithXeroSectionFragment
    , respondWithXeroToast
    , respondWithXeroTimesheetMutationAndCloseDialog
    , xeroErrorToast
    , xeroSuccessToast
    ) where

import Application.Helper.LiveUpdate (adminXeroLiveScope,
                                      setActorLiveResourcesRefresh)
import Application.Helper.Profiling
import Application.Helper.SurfaceResource (SurfaceResourceValue)
import Application.Helper.View (ToastOverlayConfig,
                                ToastOverlayPosition (ToastBottomCenter),
                                dialogOverlayMountId, errorToast,
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
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
respondWithXeroSectionFragment = do
    xeroSectionData <- fetchCurrentVenueXeroAdminSectionData
    fragmentHtml <- profileActionSpan "admin.xero.fragment.render" do
        pure (renderXeroSectionFragment xeroSectionData)
    respondHtmlProfiled fragmentHtml

fetchCurrentVenueXeroAdminSectionData ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO XeroAdminSectionData
fetchCurrentVenueXeroAdminSectionData =
    XeroReadModel.fetchCurrentVenueXeroAdminSectionData currentUserCanManageXeroIntegration

respondWithXeroSectionActorInvalidationAndToast ::
    (?context :: ControllerContext, ?request :: Request) =>
    Set.Set SurfaceResourceValue ->
    Maybe ToastOverlayConfig ->
    IO ()
respondWithXeroSectionActorInvalidationAndToast touchedResources maybeToast = do
    setActorLiveResourcesRefresh (adminXeroLiveScope (unpackId currentVenueId)) touchedResources [AdminSurface.adminXeroShellFragment]
    respondWithXeroToast maybeToast

respondWithXeroToast ::
    (?context :: ControllerContext, ?request :: Request) =>
    Maybe ToastOverlayConfig ->
    IO ()
respondWithXeroToast maybeToast =
    respondHtmlProfiled $
        maybe mempty (renderToastOverlayHostOob ToastBottomCenter . pure) maybeToast

respondWithXeroTimesheetMutationAndCloseDialog ::
    (?context :: ControllerContext, ?request :: Request) =>
    Maybe ToastOverlayConfig ->
    IO ()
respondWithXeroTimesheetMutationAndCloseDialog maybeToast =
    respondHtmlProfiled $
        mconcat
            [ [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            , maybe mempty (renderToastOverlayHostOob ToastBottomCenter . pure) maybeToast
            ]

xeroSuccessToast :: Text -> ToastOverlayConfig
xeroSuccessToast = successToast

xeroErrorToast :: Text -> ToastOverlayConfig
xeroErrorToast = errorToast

currentUserCanManageXeroIntegration :: (?context :: ControllerContext) => Bool
currentUserCanManageXeroIntegration = hasRole VenueOwnerRole

requireCurrentVenueOwnerForXero :: (?context :: ControllerContext, ?request :: Request) => IO () -> IO ()
requireCurrentVenueOwnerForXero action =
    if currentUserCanManageXeroIntegration
        then action
        else do
            setErrorMessage "Only the venue owner or a super admin can manage Xero for this venue."
            redirectToPath permissionDeniedFallbackPath

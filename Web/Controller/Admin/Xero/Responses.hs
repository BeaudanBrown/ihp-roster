module Web.Controller.Admin.Xero.Responses
    ( currentUserCanManageXeroIntegration
    , fetchCurrentVenueXeroAdminSectionData
    , requireCurrentVenueOwnerForXero
    , respondToXeroMappingMutationSuccess
    , respondToXeroPayItemsMutationSuccess
    , respondWithXeroMappingMutationError
    , respondWithXeroPayItemsMutationError
    , respondWithXeroPayItemsActorInvalidationAndToast
    , respondWithXeroPayItemsActorInvalidationAndToastAndCloseDialog
    , respondWithXeroPayItemsFragment
    , respondWithXeroPayItemsFragmentAndToast
    , respondWithXeroPayItemsFragmentAndToastAndCloseDialog
    , respondWithXeroSectionActorInvalidationAndToast
    , respondWithXeroSectionFragment
    , respondWithXeroSectionFragmentAndToast
    , respondWithXeroStaffMappingControlsAndToast
    , respondWithXeroStaffMappingToastOnly
    , respondWithXeroStaffMappingsFragment
    , respondWithXeroTimesheetMutation
    , respondWithXeroTimesheetMutationAndCloseDialog
    , respondWithXeroTimesheetsFragment
    , xeroErrorToast
    , xeroSuccessToast
    ) where

import Application.Helper.LiveUpdate (adminXeroLiveScope,
                                      setActorLiveFragmentsRefresh)
import Application.Helper.Profiling
import Application.Helper.View (ToastOverlayConfig (..),
                                ToastOverlayPosition (ToastBottomCenter),
                                dialogOverlayMountId, errorToast,
                                renderToastOverlayHostOob, successToast)
import Application.Helper.XeroAdminTypes
import Application.Xero.Admin.ReadModel hiding
                                        (fetchCurrentVenueXeroAdminSectionData)
import qualified Application.Xero.Admin.ReadModel as XeroReadModel
import qualified Web.Admin.FrontendSurface as AdminSurface
import Web.Controller.Prelude
import Web.View.Admin.Xero


respondWithXeroSectionFragment ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
respondWithXeroSectionFragment =
    respondWithXeroSectionFragmentAndToast Nothing

respondWithXeroSectionFragmentAndToast ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Maybe ToastOverlayConfig ->
    IO ()
respondWithXeroSectionFragmentAndToast maybeToast = do
    xeroSectionData <- fetchCurrentVenueXeroAdminSectionData
    fragmentHtml <- profileActionSpan "admin.xero.fragment.render" do
        pure (renderXeroSectionFragment xeroSectionData)
    respondHtmlProfiled $
        mconcat
            [ fragmentHtml
            , maybe mempty (\toast -> renderToastOverlayHostOob ToastBottomCenter [toast]) maybeToast
            ]

fetchCurrentVenueXeroAdminSectionData ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO XeroAdminSectionData
fetchCurrentVenueXeroAdminSectionData =
    XeroReadModel.fetchCurrentVenueXeroAdminSectionData currentUserCanManageXeroIntegration

respondWithXeroSectionActorInvalidationAndToast ::
    (?context :: ControllerContext, ?request :: Request) =>
    Maybe ToastOverlayConfig ->
    IO ()
respondWithXeroSectionActorInvalidationAndToast maybeToast = do
    setActorLiveFragmentsRefresh (adminXeroLiveScope (unpackId currentVenueId)) (AdminSurface.adminSurfaceWireFragments [AdminSurface.adminXeroShellFragment])
    respondHtmlProfiled $
        maybe mempty (\toast -> renderToastOverlayHostOob ToastBottomCenter [toast]) maybeToast

respondWithXeroStaffMappingsFragment ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
respondWithXeroStaffMappingsFragment = do
    xeroSectionData <- fetchCurrentVenueXeroAdminSectionData
    fragmentHtml <- profileActionSpan "admin.xero.staff_mapping.fragment.render" do
        pure (renderXeroStaffMappingsFragment xeroSectionData.xeroEmployees xeroSectionData.xeroStaffMappingRows xeroSectionData.xeroStaffMappingCounts)
    respondHtmlProfiled fragmentHtml

respondWithXeroPayItemsFragment ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
respondWithXeroPayItemsFragment =
    respondWithXeroPayItemsFragmentAndToast Nothing

respondWithXeroPayItemsFragmentAndToast ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Maybe ToastOverlayConfig ->
    IO ()
respondWithXeroPayItemsFragmentAndToast maybeToast = do
    xeroSectionData <- fetchCurrentVenueXeroAdminSectionData
    fragmentHtml <- profileActionSpan "admin.xero.pay_items.fragment.render" do
        pure (renderXeroPayItemsFragment xeroSectionData.xeroPayItemAccountCodeOptions xeroSectionData.xeroPayItemRequirements xeroSectionData.xeroImportedPayItems xeroSectionData.xeroPayItemAccountCodeSelection xeroSectionData.xeroLatestPayItemSyncRun xeroSectionData.xeroConnectionActionsAllowed)
    respondHtmlProfiled $
        mconcat
            [ fragmentHtml
            , maybe mempty (\toast -> renderToastOverlayHostOob ToastBottomCenter [toast]) maybeToast
            ]

respondWithXeroPayItemsFragmentAndToastAndCloseDialog ::
    (?context :: ControllerContext, ?request :: Request) =>
    Maybe ToastOverlayConfig ->
    IO ()
respondWithXeroPayItemsFragmentAndToastAndCloseDialog =
    respondWithXeroPayItemsActorInvalidationAndToastAndCloseDialog

respondWithXeroPayItemsActorInvalidationAndToast ::
    (?context :: ControllerContext, ?request :: Request) =>
    Maybe ToastOverlayConfig ->
    IO ()
respondWithXeroPayItemsActorInvalidationAndToast maybeToast = do
    setActorLiveFragmentsRefresh (adminXeroLiveScope (unpackId currentVenueId)) (AdminSurface.adminSurfaceWireFragments [AdminSurface.adminXeroPayItemsFragment])
    respondHtmlProfiled $
        maybe mempty (\toast -> renderToastOverlayHostOob ToastBottomCenter [toast]) maybeToast

respondWithXeroPayItemsActorInvalidationAndToastAndCloseDialog ::
    (?context :: ControllerContext, ?request :: Request) =>
    Maybe ToastOverlayConfig ->
    IO ()
respondWithXeroPayItemsActorInvalidationAndToastAndCloseDialog maybeToast = do
    setActorLiveFragmentsRefresh (adminXeroLiveScope (unpackId currentVenueId)) (AdminSurface.adminSurfaceWireFragments [AdminSurface.adminXeroPayItemsFragment])
    respondHtmlProfiled $
        mconcat
            [ [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            , maybe mempty (\toast -> renderToastOverlayHostOob ToastBottomCenter [toast]) maybeToast
            ]

respondWithXeroTimesheetsFragment ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
respondWithXeroTimesheetsFragment = do
    xeroSectionData <- fetchCurrentVenueXeroAdminSectionData
    fragmentHtml <- profileActionSpan "admin.xero.timesheets.fragment.render" do
        pure (renderXeroTimesheetsFragment xeroSectionData.xeroTimesheetPanelData)
    respondHtmlProfiled fragmentHtml

respondWithXeroStaffMappingControlsAndToast ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Maybe (Id Staff) ->
    Maybe ToastOverlayConfig ->
    IO ()
respondWithXeroStaffMappingControlsAndToast _ _ maybeToast = do
    setActorLiveFragmentsRefresh (adminXeroLiveScope (unpackId currentVenueId)) (AdminSurface.adminSurfaceWireFragments [AdminSurface.adminXeroStaffMappingsFragment])
    respondWithXeroStaffMappingToastOnly maybeToast

respondWithXeroStaffMappingToastOnly ::
    (?context :: ControllerContext, ?request :: Request) =>
    Maybe ToastOverlayConfig ->
    IO ()
respondWithXeroStaffMappingToastOnly maybeToast =
    respondHtmlProfiled $
        maybe mempty (\toast -> renderToastOverlayHostOob ToastBottomCenter [toast]) maybeToast

respondWithXeroTimesheetMutation ::
    (?context :: ControllerContext, ?request :: Request) =>
    Maybe ToastOverlayConfig ->
    IO ()
respondWithXeroTimesheetMutation maybeToast = do
    setActorLiveFragmentsRefresh (adminXeroLiveScope (unpackId currentVenueId)) (AdminSurface.adminSurfaceWireFragments [AdminSurface.adminXeroTimesheetsFragment])
    respondHtmlProfiled $
        maybe mempty (\toast -> renderToastOverlayHostOob ToastBottomCenter [toast]) maybeToast

respondWithXeroTimesheetMutationAndCloseDialog ::
    (?context :: ControllerContext, ?request :: Request) =>
    Maybe ToastOverlayConfig ->
    IO ()
respondWithXeroTimesheetMutationAndCloseDialog maybeToast = do
    setActorLiveFragmentsRefresh (adminXeroLiveScope (unpackId currentVenueId)) (AdminSurface.adminSurfaceWireFragments [AdminSurface.adminXeroTimesheetsFragment])
    respondHtmlProfiled $
        mconcat
            [ [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            , maybe mempty (\toast -> renderToastOverlayHostOob ToastBottomCenter [toast]) maybeToast
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

respondToXeroMappingMutationSuccess ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO ()
respondToXeroMappingMutationSuccess message =
    if isHtmxRequest
        then respondWithXeroSectionActorInvalidationAndToast (Just (xeroSuccessToast message))
        else do
            setSuccessMessage message
            redirectTo XeroAction

respondToXeroPayItemsMutationSuccess ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO ()
respondToXeroPayItemsMutationSuccess message =
    if isHtmxRequest
        then respondWithXeroPayItemsActorInvalidationAndToast (Just (xeroSuccessToast message))
        else do
            setSuccessMessage message
            redirectTo XeroAction

respondWithXeroMappingMutationError ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO ()
respondWithXeroMappingMutationError message =
    if isHtmxRequest
        then respondWithXeroSectionActorInvalidationAndToast (Just (xeroErrorToast message))
        else do
            setErrorMessage message
            redirectTo XeroAction

respondWithXeroPayItemsMutationError ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO ()
respondWithXeroPayItemsMutationError message =
    if isHtmxRequest
        then respondWithXeroPayItemsActorInvalidationAndToast (Just (xeroErrorToast message))
        else do
            setErrorMessage message
            redirectTo XeroAction

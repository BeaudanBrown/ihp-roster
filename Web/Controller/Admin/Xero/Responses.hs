module Web.Controller.Admin.Xero.Responses
    ( broadcastAdminXeroInvalidation
    , currentUserCanManageXeroIntegration
    , fetchCurrentVenueXeroAdminSectionData
    , renderCurrentVenueXeroSectionFragmentOob
    , requireCurrentVenueOwnerForXero
    , respondToXeroMappingMutationSuccess
    , respondWithXeroMappingMutationError
    , respondWithXeroSectionFragment
    , respondWithXeroSectionFragmentAndToast
    , respondWithXeroStaffMappingControlsAndToast
    , xeroErrorToast
    , xeroSuccessToast
    ) where

import Application.Helper.LiveUpdate
import Application.Helper.Profiling
import Application.Helper.View (ToastOverlayConfig (..),
                                ToastOverlayPosition (ToastBottomCenter),
                                errorToast, renderToastOverlayHostOob,
                                successToast)
import Application.Helper.XeroAdminTypes
import Application.Xero.Admin.ReadModel hiding
                                        (fetchCurrentVenueXeroAdminSectionData)
import qualified Application.Xero.Admin.ReadModel as XeroReadModel
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.View.Admin.Xero

broadcastAdminXeroInvalidation ::
    (?context :: ControllerContext, ?request :: Request) =>
    Id Venue ->
    IO ()
broadcastAdminXeroInvalidation venueId =
    broadcastLiveResync
        (adminXeroScope venueId)
        liveUpdateSourceClientId

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

renderCurrentVenueXeroSectionFragmentOob ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO Blaze.Html
renderCurrentVenueXeroSectionFragmentOob = do
    xeroSectionData <- fetchCurrentVenueXeroAdminSectionData
    profileActionSpan "admin.xero.fragment.render_oob" do
        pure (renderXeroSectionFragmentOob xeroSectionData)

respondWithXeroStaffMappingControlsAndToast ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Maybe (Id Staff) ->
    Maybe ToastOverlayConfig ->
    IO ()
respondWithXeroStaffMappingControlsAndToast connection maybeUnchangedStaffId maybeToast = do
    xeroEmployees <- profileActionSpan "admin.xero.staff_mapping.fetch_employees" (fetchCurrentVenueXeroEmployees (Just connection))
    xeroStaffMappingRows <- profileActionSpan "admin.xero.staff_mapping.fetch_rows" (fetchCurrentVenueXeroStaffMappingRows (Just connection))
    let xeroStaffMappingCounts = xeroStaffMappingCountsFor xeroStaffMappingRows
    controlsHtml <- profileActionSpan "admin.xero.staff_mapping.render_controls" do
        pure (renderXeroStaffMappingControlsOob maybeUnchangedStaffId xeroEmployees xeroStaffMappingRows xeroStaffMappingCounts)
    respondHtmlProfiled $
        mconcat
            [ controlsHtml
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
        then respondWithXeroSectionFragmentAndToast (Just (xeroSuccessToast message))
        else do
            setSuccessMessage message
            redirectTo XeroAction

respondWithXeroMappingMutationError ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO ()
respondWithXeroMappingMutationError message =
    if isHtmxRequest
        then respondWithXeroSectionFragmentAndToast (Just (xeroErrorToast message))
        else do
            setErrorMessage message
            redirectTo XeroAction

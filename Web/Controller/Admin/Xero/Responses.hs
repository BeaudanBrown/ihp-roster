module Web.Controller.Admin.Xero.Responses
    ( broadcastAdminXeroInvalidation
    , broadcastAdminXeroPayItemsInvalidation
    , broadcastAdminXeroTimesheetsInvalidation
    , currentUserCanManageXeroIntegration
    , fetchCurrentVenueXeroAdminSectionData
    , renderCurrentVenueXeroSectionFragmentOob
    , requireCurrentVenueOwnerForXero
    , respondToXeroMappingMutationSuccess
    , respondToXeroPayItemsMutationSuccess
    , respondWithXeroMappingMutationError
    , respondWithXeroPayItemsMutationError
    , respondWithXeroPayItemsFragment
    , respondWithXeroPayItemsFragmentAndToast
    , respondWithXeroSectionFragment
    , respondWithXeroSectionFragmentAndToast
    , respondWithXeroStaffMappingControlsAndToast
    , respondWithXeroStaffMappingToastOnly
    , respondWithXeroStaffMappingsFragment
    , respondWithXeroTimesheetMutation
    , respondWithXeroTimesheetsFragment
    , xeroPayItemsFragmentRef
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
import qualified Data.Aeson as Aeson
import qualified Data.UUID as UUID
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

broadcastAdminXeroStaffMappingsInvalidation ::
    (?context :: ControllerContext, ?request :: Request) =>
    UUID.UUID ->
    IO ()
broadcastAdminXeroStaffMappingsInvalidation venueId =
    broadcastLiveInvalidation
        AdminXeroScope { venueId }
        liveUpdateSourceClientId
        [xeroStaffMappingsFragmentRef]

broadcastAdminXeroPayItemsInvalidation ::
    (?context :: ControllerContext, ?request :: Request) =>
    UUID.UUID ->
    IO ()
broadcastAdminXeroPayItemsInvalidation venueId =
    broadcastLiveInvalidation
        AdminXeroScope { venueId }
        liveUpdateSourceClientId
        [xeroPayItemsFragmentRef]

broadcastAdminXeroTimesheetsInvalidation ::
    (?context :: ControllerContext, ?request :: Request) =>
    UUID.UUID ->
    IO ()
broadcastAdminXeroTimesheetsInvalidation venueId =
    broadcastLiveInvalidation
        AdminXeroScope { venueId }
        liveUpdateSourceClientId
        [xeroTimesheetsFragmentRef]

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
        pure (renderXeroPayItemsFragment xeroSectionData.xeroEarningsRates xeroSectionData.xeroPayItemRequirements xeroSectionData.xeroPayItemAccountCodeSelection xeroSectionData.xeroLatestPayItemSyncRun xeroSectionData.xeroConnectionActionsAllowed)
    respondHtmlProfiled $
        mconcat
            [ fragmentHtml
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
respondWithXeroStaffMappingControlsAndToast connection _ maybeToast = do
    profileActionSpan "admin.xero.staff_mapping.broadcast" $
        broadcastAdminXeroStaffMappingsInvalidation connection.venueId
    setHeader ("HX-Trigger", cs (Aeson.encode (liveFragmentsRefreshTriggerPayload [xeroStaffMappingsFragmentRef])))
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
    setHeader ("HX-Trigger", cs (Aeson.encode (liveFragmentsRefreshTriggerPayload [xeroTimesheetsFragmentRef])))
    respondHtmlProfiled $
        maybe mempty (\toast -> renderToastOverlayHostOob ToastBottomCenter [toast]) maybeToast

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

respondToXeroPayItemsMutationSuccess ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO ()
respondToXeroPayItemsMutationSuccess message =
    if isHtmxRequest
        then respondWithXeroPayItemsFragmentAndToast (Just (xeroSuccessToast message))
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

respondWithXeroPayItemsMutationError ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO ()
respondWithXeroPayItemsMutationError message =
    if isHtmxRequest
        then respondWithXeroPayItemsFragmentAndToast (Just (xeroErrorToast message))
        else do
            setErrorMessage message
            redirectTo XeroAction

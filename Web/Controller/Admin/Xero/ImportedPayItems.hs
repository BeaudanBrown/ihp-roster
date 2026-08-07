module Web.Controller.Admin.Xero.ImportedPayItems
    ( importXeroPayItemsAction
    , openXeroPayItemImportAction
    ) where

import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.View (ToastOverlayConfig (..),
                                ToastOverlayPosition (ToastBottomCenter),
                                dialogOverlayMountId, renderToastOverlayHostOob)
import Application.Helper.Xero (XeroEarningsRateRef (..))
import Application.Xero.Admin.ImportedPayItems
import Application.Xero.Admin.ReadModel (fetchCurrentVenueXeroConnection)
import Application.Xero.ReferenceTrust
import Application.Xero.ReferenceTrust.ReadModel (XeroReferenceTrustState (..))
import Application.Xero.ReferenceTrust.Service
import Web.Admin.Xero.Mutations
import Web.Controller.Admin.Xero.Responses (xeroErrorToast, xeroSuccessToast)
import Web.Controller.Prelude
import Web.View.Admin.Xero.ImportedPayItems (renderXeroImportedPayItemImportDialog,
                                             renderXeroImportedPayItemImportErrorDialog,
                                             renderXeroImportedPayItemImportLoadingDialog,
                                             renderXeroImportedPayItemImportWaitingDialog)

openXeroPayItemImportAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
openXeroPayItemImportAction = do
    let shouldLoadCandidates = paramOrDefault @Bool False "loadCandidates"
    let maybeWaitStartedAt = paramOrNothing @UTCTime "referenceWaitStartedAt"
    if isHtmxRequest && not shouldLoadCandidates
        then respondHtml renderXeroImportedPayItemImportLoadingDialog
        else
            withTrustedXeroEarningsRates respondImportedPayItemDialogError (respondImportedPayItemWaiting maybeWaitStartedAt) \connection _now fetchedRates -> do
                activeImports <- fetchActiveImportedXeroPayItems connection
                respondHtml (renderXeroImportedPayItemImportDialog (viableImportedPayItemCandidates activeImports fetchedRates))

importXeroPayItemsAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
importXeroPayItemsAction = do
    let selectedRateIds = paramList @Text "xeroEarningsRateId"
    withTrustedXeroEarningsRates respondImportedPayItemDialogToast (\_ _ -> respondImportedPayItemDialogToast (xeroErrorToast "Xero payroll reference data is syncing in the background.")) \connection now fetchedRates -> do
        let availableRateIds = map (.xeroEarningsRateId) fetchedRates
            submittedUnavailableRateIds = filter (`notElem` availableRateIds) selectedRateIds
        if null selectedRateIds
            then respondImportValidationError connection fetchedRates "Choose at least one Xero pay item to import."
            else if not (null submittedUnavailableRateIds)
                then respondImportValidationError connection fetchedRates "A selected Xero pay item is no longer available. Refresh the dialog and choose a current pay item."
                else do
                    LiveMutationResult { liveMutationValue = imported } <- importXeroEarningsRatesMutation connection now fetchedRates selectedRateIds
                    respondImportedPayItemImportSuccess (Just (xeroSuccessToast ("Imported " <> tshow (length imported) <> " Xero pay item" <> pluralSuffix imported <> ".")))

withTrustedXeroEarningsRates :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => (ToastOverlayConfig -> IO ()) -> (UTCTime -> XeroReferenceTrustState -> IO ()) -> (XeroConnection -> UTCTime -> [XeroEarningsRateRef] -> IO ()) -> IO ()
withTrustedXeroEarningsRates respondError respondWaiting action = do
    maybeConnection <- fetchCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> respondError (xeroErrorToast "Connect Xero before importing pay items.")
        Just connection -> do
            now <- getCurrentTime
            trustState <- requestTrustedXeroReferenceData now (Just currentUser.id) connection NoMissingPayrollReferenceDemand
            case trustState.trustDecision of
                UseTrustedXeroReferenceSnapshot -> do
                    syncedRates <- fetchSyncedXeroEarningsRateRefs connection
                    action connection now syncedRates
                StartOrJoinXeroReferenceSync -> respondWaiting now trustState
                WaitForTrustedXeroReferenceSnapshot _ -> respondWaiting now trustState
                ReconnectXeroForReferenceData -> respondError (xeroErrorToast "Reconnect Xero before importing pay items.")
                BlockStaleXeroReferenceData _ -> respondError (xeroErrorToast "Xero reference data is out of date and could not be refreshed. Contact support before importing pay items.")

respondImportValidationError ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    [XeroEarningsRateRef] ->
    Text ->
    IO ()
respondImportValidationError connection fetchedRates message = do
    activeImports <- fetchActiveImportedXeroPayItems connection
    respondImportedPayItemDialog (viableImportedPayItemCandidates activeImports fetchedRates) (Just (xeroErrorToast message))

respondImportedPayItemWaiting :: (?context :: ControllerContext, ?request :: Request) => Maybe UTCTime -> UTCTime -> XeroReferenceTrustState -> IO ()
respondImportedPayItemWaiting maybeWaitStartedAt now trustState =
    if isHtmxRequest
        then respondHtml (renderXeroImportedPayItemImportWaitingDialog now (fromMaybe now maybeWaitStartedAt) trustState)
        else do
            setSuccessMessage "Xero payroll reference data is syncing in the background."
            redirectTo XeroAction

respondImportedPayItemImportSuccess :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe ToastOverlayConfig -> IO ()
respondImportedPayItemImportSuccess maybeToast =
    if isHtmxRequest
        then respondHtml $
            mconcat
                [ [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
                , maybe mempty (renderToastOverlayHostOob ToastBottomCenter . pure) maybeToast
                ]
        else do
            setSuccessMessage "Updated imported Xero pay items."
            redirectTo XeroAction

respondImportedPayItemDialog :: (?context :: ControllerContext, ?request :: Request) => [XeroImportedPayItemCandidate] -> Maybe ToastOverlayConfig -> IO ()
respondImportedPayItemDialog candidates maybeToast =
    if isHtmxRequest
        then respondHtml $
            mconcat
                [ renderXeroImportedPayItemImportDialog candidates
                , maybe mempty (\toast -> renderToastOverlayHostOob ToastBottomCenter [toast]) maybeToast
                ]
        else do
            maybe (pure ()) (setErrorMessage . (.toastOverlayMessage)) maybeToast
            redirectTo XeroAction

respondImportedPayItemDialogToast :: (?context :: ControllerContext, ?request :: Request) => ToastOverlayConfig -> IO ()
respondImportedPayItemDialogToast toast =
    if isHtmxRequest
        then respondHtml (renderToastOverlayHostOob ToastBottomCenter [toast])
        else do
            setErrorMessage toast.toastOverlayMessage
            redirectTo XeroAction

respondImportedPayItemDialogError :: (?context :: ControllerContext, ?request :: Request) => ToastOverlayConfig -> IO ()
respondImportedPayItemDialogError toast =
    if isHtmxRequest
        then respondHtml $
            mconcat
                [ renderXeroImportedPayItemImportErrorDialog toast.toastOverlayMessage
                , renderToastOverlayHostOob ToastBottomCenter [toast]
                ]
        else do
            setErrorMessage toast.toastOverlayMessage
            redirectTo XeroAction

pluralSuffix :: [a] -> Text
pluralSuffix [_] = ""
pluralSuffix _   = "s"

module Web.Controller.Admin.Xero.ImportedPayItems
    ( importXeroPayItemsAction
    , openXeroPayItemImportAction
    , showXeroPayItemImportWaitFragmentAction
    ) where

import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.View (ToastOverlayConfig (..),
                                ToastOverlayPosition (ToastBottomCenter),
                                renderDialogOverlayClearOob,
                                renderToastOverlayHostOob)
import Application.Helper.Xero (XeroEarningsRateRef (..))
import Application.Xero.Admin.ImportedPayItems
import Application.Xero.Admin.ReadModel (fetchCurrentVenueXeroConnection)
import Application.Xero.ReferenceTrust
import Application.Xero.ReferenceTrust.Presentation (XeroPayItemImportReferencePresentation (..),
                                                     xeroPayItemImportReferencePresentation)
import Application.Xero.ReferenceTrust.ReadModel (XeroReferenceTrustState (..),
                                                  fetchXeroReferenceTrustState)
import Application.Xero.ReferenceTrust.Service
import Web.Admin.Xero.Mutations
import Web.Controller.Admin.Xero.Responses (xeroErrorToast, xeroSuccessToast)
import Web.Controller.Prelude
import Web.View.Admin.Xero.ImportedPayItems (renderXeroImportedPayItemImportCandidatesWaitFragment,
                                             renderXeroImportedPayItemImportDialog,
                                             renderXeroImportedPayItemImportErrorDialog,
                                             renderXeroImportedPayItemImportErrorWaitFragment,
                                             renderXeroImportedPayItemImportWaitFragment,
                                             renderXeroImportedPayItemImportWaitingDialog)

openXeroPayItemImportAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
openXeroPayItemImportAction =
    withTrustedXeroEarningsRates respondImportedPayItemDialogError respondImportedPayItemWaiting \connection _now fetchedRates -> do
        candidates <- fetchXeroImportedPayItemCandidates connection fetchedRates
        respondHtml (renderXeroImportedPayItemImportDialog candidates)

showXeroPayItemImportWaitFragmentAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
showXeroPayItemImportWaitFragmentAction = do
    maybeConnection <- fetchCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> respondHtml (renderXeroImportedPayItemImportErrorWaitFragment "Connect Xero before importing pay items.")
        Just connection -> do
            now <- getCurrentTime
            trustState <- fetchXeroReferenceTrustState now connection NoMissingPayrollReferenceDemand
            case xeroPayItemImportReferencePresentation trustState.trustDecision of
                XeroPayItemImportReferenceReady -> do
                    fetchedRates <- fetchSyncedXeroEarningsRateRefs connection
                    candidates <- fetchXeroImportedPayItemCandidates connection fetchedRates
                    respondHtml (renderXeroImportedPayItemImportCandidatesWaitFragment candidates)
                XeroPayItemImportReferenceWaiting -> respondHtml (renderXeroImportedPayItemImportWaitFragment trustState)
                XeroPayItemImportReferenceBlocked message -> respondHtml (renderXeroImportedPayItemImportErrorWaitFragment message)

importXeroPayItemsAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
importXeroPayItemsAction = do
    let selectedRateIds = paramList @Text "xeroEarningsRateId"
    withTrustedXeroEarningsRates respondImportedPayItemDialogToast (\_ -> respondImportedPayItemDialogToast (xeroErrorToast "Xero payroll reference data is syncing in the background.")) \connection now fetchedRates -> do
        let availableRateIds = map (.xeroEarningsRateId) fetchedRates
            submittedUnavailableRateIds = filter (`notElem` availableRateIds) selectedRateIds
        if null selectedRateIds
            then respondImportValidationError connection fetchedRates "Choose at least one Xero pay item to import."
            else if not (null submittedUnavailableRateIds)
                then respondImportValidationError connection fetchedRates "A selected Xero pay item is no longer available. Refresh the dialog and choose a current pay item."
                else do
                    LiveMutationResult { liveMutationValue = imported } <- importXeroEarningsRatesMutation connection now fetchedRates selectedRateIds
                    respondImportedPayItemImportSuccess (Just (xeroSuccessToast ("Imported " <> tshow (length imported) <> " Xero pay item" <> pluralSuffix imported <> ".")))

withTrustedXeroEarningsRates :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => (ToastOverlayConfig -> IO ()) -> (XeroReferenceTrustState -> IO ()) -> (XeroConnection -> UTCTime -> [XeroEarningsRateRef] -> IO ()) -> IO ()
withTrustedXeroEarningsRates respondError respondWaiting action = do
    maybeConnection <- fetchCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> respondError (xeroErrorToast "Connect Xero before importing pay items.")
        Just connection -> do
            now <- getCurrentTime
            trustState <- requestTrustedXeroReferenceData now (Just currentUser.id) connection NoMissingPayrollReferenceDemand
            case xeroPayItemImportReferencePresentation trustState.trustDecision of
                XeroPayItemImportReferenceReady -> do
                    syncedRates <- fetchSyncedXeroEarningsRateRefs connection
                    action connection now syncedRates
                XeroPayItemImportReferenceWaiting -> respondWaiting trustState
                XeroPayItemImportReferenceBlocked message -> respondError (xeroErrorToast message)

fetchXeroImportedPayItemCandidates :: (?context :: ControllerContext, ?modelContext :: ModelContext) => XeroConnection -> [XeroEarningsRateRef] -> IO [XeroImportedPayItemCandidate]
fetchXeroImportedPayItemCandidates connection fetchedRates = do
    activeImports <- fetchActiveImportedXeroPayItems connection
    pure (viableImportedPayItemCandidates activeImports fetchedRates)

respondImportValidationError ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    [XeroEarningsRateRef] ->
    Text ->
    IO ()
respondImportValidationError connection fetchedRates message = do
    candidates <- fetchXeroImportedPayItemCandidates connection fetchedRates
    respondImportedPayItemDialog candidates (Just (xeroErrorToast message))

respondImportedPayItemWaiting :: (?context :: ControllerContext, ?request :: Request) => XeroReferenceTrustState -> IO ()
respondImportedPayItemWaiting trustState =
    if isHtmxRequest
        then respondHtml (renderXeroImportedPayItemImportWaitingDialog (unpackId currentVenueId) trustState)
        else do
            setSuccessMessage "Xero payroll reference data is syncing in the background."
            redirectTo XeroAction

respondImportedPayItemImportSuccess :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe ToastOverlayConfig -> IO ()
respondImportedPayItemImportSuccess maybeToast =
    if isHtmxRequest
        then respondHtml $
            mconcat
                [ renderDialogOverlayClearOob
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

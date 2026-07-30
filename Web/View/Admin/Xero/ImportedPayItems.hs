{-# LANGUAGE TypeApplications #-}

module Web.View.Admin.Xero.ImportedPayItems
    ( renderXeroImportedPayItemImportDialog
    , renderXeroImportedPayItemImportErrorDialog
    , renderXeroImportedPayItemImportLoadingDialog
    , renderXeroImportedPayItemImportWaitingDialog
    ) where

import Application.Helper.FrontendContract.AppShell (ImportXeroPayItemsOverlay,
                                                     LoadXeroPayItemImportOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             AppShellFieldValue (..),
                                                             appShellActionByMarker,
                                                             renderAppShellActionForm)
import Application.Helper.FrontendContract.XeroCandidateFilter.Runtime
import Application.Helper.Xero (XeroEarningsRateRef (..))
import Application.Xero.Admin.ImportedPayItems (XeroImportedPayItemCandidate (..))
import Application.Xero.ReferenceTrust (XeroReferenceSyncProgressFacts (..))
import Application.Xero.ReferenceTrust.Presentation
import Application.Xero.ReferenceTrust.ReadModel (XeroReferenceTrustState (..))
import Data.Scientific (FPFormat (Fixed), Scientific, formatScientific)
import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.View.Prelude

xeroPayItemAppShellActionRoute :: Text -> AppShellActionRoute
xeroPayItemAppShellActionRoute actionUrl =
    AppShellActionRoute
        { appShellActionRouteUrl = actionUrl
        , appShellActionRouteFields = []
        , appShellActionRouteCustomHtmx = []
        , appShellActionRouteStandardUrl = Nothing
        , appShellActionRouteExtraAttrs = []
        }

renderXeroImportedPayItemImportLoadingDialog :: Html
renderXeroImportedPayItemImportLoadingDialog =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Import Xero pay items"
        , dialogOverlayBody = [hsx|
            <div class="d-flex align-items-center gap-3">
                <div id="xero-import-pay-items-loading-indicator" class="spinner-border text-primary" role="status" aria-hidden="true"></div>
                <div>
                    <div class="fw-semibold">Fetching Xero pay items...</div>
                    <div class="small app-muted">Bepis is checking trusted Xero reference data before loading supported hourly earnings rates.</div>
                </div>
                {renderLoadXeroPayItemImportForm Nothing}
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = []
        , dialogOverlayDialogClass = ""
        }

renderXeroImportedPayItemImportWaitingDialog :: UTCTime -> UTCTime -> XeroReferenceTrustState -> Html
renderXeroImportedPayItemImportWaitingDialog now waitStartedAt trustState =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Import Xero pay items"
        , dialogOverlayBody = [hsx|
            <div class="d-flex align-items-start gap-3" data-xero-reference-sync-waiting="true">
                <div id="xero-import-pay-items-loading-indicator" class="spinner-border text-primary mt-1" role="status" aria-hidden="true"></div>
                <div class="d-flex flex-column gap-1">
                    <div class="fw-semibold">Refreshing Xero reference data</div>
                    <div>{xeroReferenceSyncActivityText trustState.syncActivity}</div>
                    {renderReferenceSyncPhase trustState.syncProgress.progressPhase}
                    {renderCompletedPayItemsPage trustState.syncProgress.progressCompletedPayItemsPage}
                    {renderReferenceWaitDurationNotice now waitStartedAt}
                </div>
                {renderLoadXeroPayItemImportForm (Just waitStartedAt)}
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ OverlayButton
                { overlayButtonLabel = "Close"
                , overlayButtonClass = "btn btn-outline-secondary"
                , overlayButtonAction = OverlayCloseAction
                }
            ]
        , dialogOverlayDialogClass = ""
        }

renderReferenceWaitDurationNotice :: UTCTime -> UTCTime -> Html
renderReferenceWaitDurationNotice now waitStartedAt
    | xeroReferenceWaitIsLongRunning now waitStartedAt = [hsx|
        <div class="small app-muted"><strong>Taking longer than usual.</strong> The refresh continues in the background and this dialog will keep checking for trusted data.</div>
    |]
    | otherwise = [hsx|<div class="small app-muted">This dialog will continue automatically when trusted reference data is ready.</div>|]

renderReferenceSyncPhase :: Maybe Text -> Html
renderReferenceSyncPhase Nothing = mempty
renderReferenceSyncPhase (Just phase) = [hsx|<div class="small app-muted">{xeroReferenceSyncPhaseText phase}</div>|]

renderCompletedPayItemsPage :: Maybe Int -> Html
renderCompletedPayItemsPage Nothing = mempty
renderCompletedPayItemsPage (Just page) = [hsx|<div class="small app-muted">Completed page {page}</div>|]

renderLoadXeroPayItemImportForm :: Maybe UTCTime -> Html
renderLoadXeroPayItemImportForm maybeWaitStartedAt =
    renderAppShellActionForm
        (appShellActionByMarker @LoadXeroPayItemImportOverlay)
        (xeroPayItemAppShellActionRoute (pathTo OpenXeroPayItemImportAction))
            { appShellActionRouteFields =
                [AppShellFieldValue ("loadCandidates", "true")]
                    <> maybe [] (\waitStartedAt -> [AppShellFieldValue ("referenceWaitStartedAt", cs (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" waitStartedAt))]) maybeWaitStartedAt
            }
        mempty

renderXeroImportedPayItemImportErrorDialog :: Text -> Html
renderXeroImportedPayItemImportErrorDialog message =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Import Xero pay items"
        , dialogOverlayBody = [hsx|
            <div class="alert alert-danger mb-0">{message}</div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ OverlayButton
                { overlayButtonLabel = "Close"
                , overlayButtonClass = "btn btn-outline-secondary"
                , overlayButtonAction = OverlayCloseAction
                }
            ]
        , dialogOverlayDialogClass = ""
        }

renderXeroImportedPayItemImportDialog :: [XeroImportedPayItemCandidate] -> Html
renderXeroImportedPayItemImportDialog candidates =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Import Xero pay items"
        , dialogOverlayBody = [hsx|
            {renderImportXeroPayItemsForm candidates}
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ OverlayButton
                { overlayButtonLabel = "Cancel"
                , overlayButtonClass = "btn btn-outline-secondary"
                , overlayButtonAction = OverlayCloseAction
                }
            , OverlayButton
                { overlayButtonLabel = "Import selected"
                , overlayButtonClass = classes [("btn btn-primary", True), ("disabled", null candidates)]
                , overlayButtonAction = OverlaySubmitFormAction "xero-imported-pay-items-import-form"
                }
            ]
        , dialogOverlayDialogClass = "modal-lg modal-dialog-scrollable"
        }

renderImportXeroPayItemsForm :: [XeroImportedPayItemCandidate] -> Html
renderImportXeroPayItemsForm candidates =
    renderAppShellActionForm
        (appShellActionByMarker @ImportXeroPayItemsOverlay)
        (xeroPayItemAppShellActionRoute (pathTo ImportXeroPayItemsAction))
            { appShellActionRouteExtraAttrs = [("id", "xero-imported-pay-items-import-form")]
            }
        [hsx|
            <p class="small app-muted">Only active hourly ordinary earnings rates that were not generated by Bepis and have not already been imported are shown.</p>
            <div {...xeroCandidateFilterRootAttrs}>
                <input type="search"
                       class="form-control form-control-sm mb-3"
                       placeholder="Search pay items"
                       aria-label="Search pay items"
                       {...xeroCandidateFilterSearchAttrs}>
                {renderImportCandidateList candidates}
            </div>
        |]

renderImportCandidateList :: [XeroImportedPayItemCandidate] -> Html
renderImportCandidateList [] = [hsx|<div class="alert alert-secondary small mb-0">No new supported Xero pay items are available to import.</div>|]
renderImportCandidateList candidates = [hsx|
    <div class="list-group">
        {forEach candidates renderImportCandidate}
    </div>
    <div class="alert alert-secondary small mt-3 mb-0"
         role="status"
         aria-live="polite"
         hidden="hidden"
         {...xeroCandidateFilterEmptyAttrs}>
        No pay items match your search.
    </div>
|]

renderImportCandidate :: XeroImportedPayItemCandidate -> Html
renderImportCandidate XeroImportedPayItemCandidate { candidateEarningsRate = rate } = [hsx|
    <label class="list-group-item d-flex gap-2 align-items-start" {...xeroCandidateFilterCandidateAttrs searchProjection}>
        <input class="form-check-input mt-1" type="checkbox" name="xeroEarningsRateId" value={rateId}>
        <span class="flex-grow-1">
            <span class="fw-semibold d-block">{rate.xeroEarningsRateName}</span>
            <span class="small app-muted">{fromMaybe "No account" rate.xeroEarningsRateAccountCode} · ${maybe "—" formatMoney rate.xeroEarningsRateRatePerUnit}/hr</span>
        </span>
    </label>
|]
    where
        rateId :: Text
        rateId = rate.xeroEarningsRateId
        searchProjection :: XeroCandidateSearchProjection
        searchProjection =
            xeroCandidateSearchProjection
                [ rate.xeroEarningsRateName
                , fromMaybe "" rate.xeroEarningsRateAccountCode
                ]

formatMoney :: Scientific -> Text
formatMoney =
    Text.pack . formatScientific Fixed (Just 2)

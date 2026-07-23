{-# LANGUAGE TypeApplications #-}

module Web.View.Billing.Index where

import Application.Helper.Controller (currentVenueOrNothing)
import qualified Application.Helper.FrontendContract.Surface.Billing as Surface
import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values (SurfaceFields,
                                                           noSurfaceFields,
                                                           surfaceFragmentTargetId)
import qualified Data.Text as Text
import Web.Billing.FrontendSurface (BillingCheckoutReturnState (..),
                                    billingSurfaceImpl,
                                    currentBillingScopeValue)
import Web.View.Prelude

data BillingViewModel = BillingViewModel
    { maybeCustomer            :: !(Maybe VenueBillingCustomer)
    , maybeSubscription        :: !(Maybe VenueSubscription)
    , maybeControl             :: !(Maybe VenueBillingControl)
    , recentEvents             :: ![BillingEvent]
    , recentReconciliationJobs :: ![AppJob]
    , checkoutReturn           :: !(Maybe BillingCheckoutReturn)
    , stripeCheckoutAvailable  :: !Bool
    }

data BillingCheckoutReturn = BillingCheckoutReturn
    { checkoutAttemptId :: !Text
    , checkoutSessionId :: !(Maybe Text)
    , checkoutOutcome   :: !BillingCheckoutOutcome
    }

data BillingCheckoutOutcome
    = BillingCheckoutPending
    | BillingCheckoutConfirmed !VenueSubscription
    | BillingCheckoutFailed !BillingCheckoutAttempt

newtype BillingView = BillingView
    { viewModel :: BillingViewModel
    }

data BillingSuccessView = BillingSuccessView

data BillingCancelView = BillingCancelView

instance View BillingView where
    html BillingView { viewModel } =
        renderAppPage AppPageConfig
            { appPageTitle = "Billing"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageHelpTopic = Just (PageHelpTopicId "billing")
            , appPageWidthClass = ""
            , appPageBody = [hsx|
                <div id="billing-live-surface" class="app-page-stack">
                    {renderFrontendSurfaceMount (billingSurfaceImpl currentBillingScopeValue (billingCheckoutReturnState viewModel.checkoutReturn)) (renderbillingStatusLiveFragment viewModel)}
                </div>
            |]
            }

instance View BillingSuccessView where
    html BillingSuccessView =
        renderBillingResultPage
            "Billing Pending"
            "Stripe is finalising the subscription. The venue billing status will update after the signed webhook is processed."

instance View BillingCancelView where
    html BillingCancelView =
        renderBillingResultPage
            "Billing Cancelled"
            "No subscription change was confirmed by this browser return. You can go back to Billing and resume this Checkout while it remains available."

renderBillingResultPage :: Text -> Text -> Html
renderBillingResultPage title message =
    renderAppPage AppPageConfig
        { appPageTitle = title
        , appPageDescription = Nothing
        , appPageActions = [hsx|<a class="btn btn-outline-secondary" href={BillingAction}>Back to Billing</a>|]
        , appPageHelpTopic = Just (PageHelpTopicId "billing")
        , appPageWidthClass = "app-form-width"
        , appPageBody =
            simpleAppPanel title Nothing [hsx|
                <p class="mb-0 app-muted">{message}</p>
            |]
        }

renderbillingStatusLiveFragment :: BillingViewModel -> Html
renderbillingStatusLiveFragment viewModel@BillingViewModel { recentEvents, recentReconciliationJobs, maybeControl, checkoutReturn } = [hsx|
    <div id={surfaceFragmentTargetId @Surface.BillingSurface @Surface.BillingStatus noSurfaceFields}>
        {renderBillingStatusPanel viewModel}
        {if currentUserIsSupportAdmin then renderBillingReconciliationPanel recentReconciliationJobs else mempty}
        {if currentUserIsSupportAdmin then renderBillingControlPanel maybeControl else mempty}
        {renderBillingEventsPanel recentEvents}
        {renderBillingCheckoutReturnDialog checkoutReturn}
    </div>
|]

billingCheckoutReturnState :: Maybe BillingCheckoutReturn -> BillingCheckoutReturnState
billingCheckoutReturnState Nothing =
    BillingCheckoutReturnState
        { billingCheckoutReturned = False
        , billingCheckoutAttemptId = Nothing
        , billingCheckoutSessionId = Nothing
        }
billingCheckoutReturnState (Just BillingCheckoutReturn { checkoutAttemptId, checkoutSessionId }) =
    BillingCheckoutReturnState
        { billingCheckoutReturned = True
        , billingCheckoutAttemptId = Just checkoutAttemptId
        , billingCheckoutSessionId = checkoutSessionId
        }

renderBillingCheckoutReturnDialog :: Maybe BillingCheckoutReturn -> Html
renderBillingCheckoutReturnDialog Nothing = mempty
renderBillingCheckoutReturnDialog (Just checkoutReturn) =
    renderPageDialogModal (pathTo BillingAction) DialogOverlayConfig
        { dialogOverlayTitle = billingCheckoutDialogTitle checkoutReturn.checkoutOutcome
        , dialogOverlayBody = renderBillingCheckoutDialogBody checkoutReturn
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = billingCheckoutDialogButtons checkoutReturn.checkoutOutcome
        , dialogOverlayDialogClass = "modal-dialog-centered"
        }

billingCheckoutDialogTitle :: BillingCheckoutOutcome -> Text
billingCheckoutDialogTitle BillingCheckoutPending = "Finalising subscription"
billingCheckoutDialogTitle (BillingCheckoutConfirmed _) = "Subscription confirmed"
billingCheckoutDialogTitle (BillingCheckoutFailed _) = "Subscription needs attention"

billingCheckoutDialogButtons :: BillingCheckoutOutcome -> [OverlayButton]
billingCheckoutDialogButtons BillingCheckoutPending = []
billingCheckoutDialogButtons (BillingCheckoutConfirmed _) =
    [ OverlayButton
        { overlayButtonLabel = "Continue"
        , overlayButtonClass = "btn btn-primary"
        , overlayButtonAction = OverlayNavigateAction (pathTo BillingAction)
        }
    ]
billingCheckoutDialogButtons (BillingCheckoutFailed _) =
    [ OverlayButton
        { overlayButtonLabel = "Back to Billing"
        , overlayButtonClass = "btn btn-outline-secondary"
        , overlayButtonAction = OverlayNavigateAction (pathTo BillingAction)
        }
    , OverlayButton
        { overlayButtonLabel = "Try Checkout Again"
        , overlayButtonClass = "btn btn-primary"
        , overlayButtonAction = DialogFormAction "POST" (pathTo CreateBillingCheckoutSessionAction) [] Nothing
        }
    ]

renderBillingCheckoutDialogBody :: BillingCheckoutReturn -> Html
renderBillingCheckoutDialogBody BillingCheckoutReturn { checkoutSessionId, checkoutOutcome = BillingCheckoutPending } = [hsx|
    <div class="d-flex gap-3 align-items-start">
        <div class="spinner-border text-primary flex-shrink-0" role="status" aria-label="Loading"></div>
        <div>
            <p class="mb-2">Stripe has returned you to Bepis. We are waiting for the signed webhook to confirm the subscription.</p>
            <p class="mb-0 app-muted small">This usually takes a few seconds. You can leave this page open; it will update automatically.</p>
            {renderCheckoutSessionHint checkoutSessionId}
        </div>
    </div>
|]
renderBillingCheckoutDialogBody BillingCheckoutReturn { checkoutOutcome = BillingCheckoutConfirmed subscription } = [hsx|
    <p class="mb-2">Stripe confirmed the subscription and Bepis has updated this venue's billing status.</p>
    <div class="small app-muted">Subscription: {subscription.stripeSubscriptionId}</div>
|]
renderBillingCheckoutDialogBody BillingCheckoutReturn { checkoutOutcome = BillingCheckoutFailed attempt } = [hsx|
    <p class="mb-2">Stripe sent an update for this checkout, but Bepis could not confirm the subscription automatically.</p>
    <div class="small app-muted">Checkout attempt: {inputValue attempt.id} · {attempt.status}</div>
    {renderBillingCheckoutErrorSummary attempt.errorSummary}
|]

renderBillingCheckoutErrorSummary :: Maybe Text -> Html
renderBillingCheckoutErrorSummary Nothing = mempty
renderBillingCheckoutErrorSummary (Just summary) = [hsx|
    <div class="small text-danger mt-2">{summary}</div>
|]

renderCheckoutSessionHint :: Maybe Text -> Html
renderCheckoutSessionHint Nothing = mempty
renderCheckoutSessionHint (Just sessionId) = [hsx|
    <div class="small app-muted mt-2">Checkout session: {sessionId}</div>
|]

renderBillingStatusPanel :: BillingViewModel -> Html
renderBillingStatusPanel BillingViewModel { maybeCustomer, maybeSubscription, stripeCheckoutAvailable } =
    simpleAppPanel
        "Subscription"
        (Just "Stripe-hosted Checkout and Customer Portal manage payment details outside this app.")
        [hsx|
            <div class="d-flex flex-column gap-3">
                <div class="table-responsive">
                    <table class="table table-sm align-middle mb-0">
                        <tbody>
                            <tr>
                                <th scope="row" class="w-25">Venue</th>
                                <td>{currentVenueName}</td>
                            </tr>
                            <tr>
                                <th scope="row">Customer</th>
                                <td>{maybe "Not created" (.stripeCustomerId) maybeCustomer}</td>
                            </tr>
                            <tr>
                                <th scope="row">Subscription</th>
                                <td>{renderSubscriptionSummary maybeSubscription}</td>
                            </tr>
                            <tr>
                                <th scope="row">Price</th>
                                <td>AUD 100/month</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
                <div class="d-flex flex-wrap gap-2">
                    <form method="POST" action={CreateBillingCheckoutSessionAction}>
                        <button type="submit" class="btn btn-primary" disabled={not stripeCheckoutAvailable}>Start Subscription</button>
                    </form>
                    <form method="POST" action={CreateBillingPortalSessionAction}>
                        <button type="submit" class="btn btn-outline-primary" disabled={isNothing maybeCustomer}>Manage Billing</button>
                    </form>
                </div>
                {renderCheckoutAvailability stripeCheckoutAvailable}
            </div>
        |]

renderCheckoutAvailability :: Bool -> Html
renderCheckoutAvailability True = mempty
renderCheckoutAvailability False = [hsx|
    <p class="mb-0 app-muted small">New subscriptions are temporarily unavailable. Existing customers can still manage billing.</p>
|]

renderSubscriptionSummary :: Maybe VenueSubscription -> Html
renderSubscriptionSummary Nothing = [hsx|No webhook-confirmed subscription|]
renderSubscriptionSummary (Just subscription) = [hsx|
    <div class="d-flex flex-column gap-1">
        <div><span class="badge text-bg-secondary">{subscription.status}</span></div>
        <div class="small app-muted">{subscription.stripeSubscriptionId}</div>
        <div class="small app-muted">Current period: {formatMaybeTime subscription.currentPeriodStart} to {formatMaybeTime subscription.currentPeriodEnd}</div>
    </div>
|]

renderBillingReconciliationPanel :: [AppJob] -> Html
renderBillingReconciliationPanel jobs =
    simpleAppPanel
        "Stripe Synchronization"
        (Just "Founder support can queue a read-only refresh of this venue's known Stripe state. Reconciliation never changes venue writability.")
        [hsx|
            <div class="d-flex flex-column gap-3">
                <form method="POST" action={ReconcileVenueBillingAction}>
                    <button type="submit" class="btn btn-outline-primary">Synchronize with Stripe</button>
                </form>
                {renderBillingReconciliationJobs jobs}
            </div>
        |]

renderBillingReconciliationJobs :: [AppJob] -> Html
renderBillingReconciliationJobs [] = [hsx|
    <p class="mb-0 app-muted small">No billing synchronization has been queued for this venue.</p>
|]
renderBillingReconciliationJobs jobs = [hsx|
    <div class="table-responsive">
        <table class="table table-sm align-middle mb-0">
            <thead>
                <tr>
                    <th>Queued</th>
                    <th>Status</th>
                    <th>Job</th>
                    <th>Diagnostic</th>
                </tr>
            </thead>
            <tbody>{forEach jobs renderBillingReconciliationJobRow}</tbody>
        </table>
    </div>
|]

renderBillingReconciliationJobRow :: AppJob -> Html
renderBillingReconciliationJobRow appJob =
    let presentation = reconciliationJobStatusPresentation appJob.status
     in [hsx|
        <tr>
            <td class="small">{tshow appJob.createdAt}</td>
            <td><span class={presentation.statusBadgeClass}>{presentation.statusLabel}</span></td>
            <td class="small app-muted">{inputValue appJob.id}</td>
            <td class="small text-danger">{reconciliationTerminalDiagnostic appJob}</td>
        </tr>
    |]

data ReconciliationJobStatusPresentation = ReconciliationJobStatusPresentation
    { statusLabel      :: !Text
    , statusBadgeClass :: !Text
    }

reconciliationJobStatusPresentation :: JobStatus -> ReconciliationJobStatusPresentation
reconciliationJobStatusPresentation status =
    case inputValue status of
        "job_status_not_started" -> presentation "queued" "text-bg-secondary"
        "job_status_running"     -> presentation "running" "text-bg-secondary"
        "job_status_retry"       -> presentation "retrying" "text-bg-warning"
        "job_status_succeeded"   -> presentation "succeeded" "text-bg-success"
        "job_status_failed"      -> presentation "failed" "text-bg-danger"
        "job_status_timed_out"   -> presentation "timed out" "text-bg-danger"
        other                    -> presentation other "text-bg-secondary"
  where
    presentation statusLabel badgeClass =
        ReconciliationJobStatusPresentation
            { statusLabel
            , statusBadgeClass = "badge " <> badgeClass
            }

reconciliationTerminalDiagnostic :: AppJob -> Text
reconciliationTerminalDiagnostic appJob
    | inputValue appJob.status `elem` ["job_status_failed", "job_status_timed_out"] =
        maybe "No diagnostic recorded." (Text.take 1000) appJob.lastError
    | otherwise = ""

renderBillingControlPanel :: Maybe VenueBillingControl -> Html
renderBillingControlPanel maybeControl =
    simpleAppPanel
        "Manual Controls"
        (Just "Founder support can mark a venue read-only manually. Stripe status does not change this flag in v1.")
        [hsx|
            <form method="POST" action={UpdateVenueBillingControlAction} class="d-flex flex-column gap-3">
                <div>
                    {renderBillingManualReadOnlyToggle (maybe False (.manualReadOnly) maybeControl)}
                </div>
                <div>
                    <label class="form-label" for="billing-manual-read-only-reason">Reason</label>
                    <textarea
                        id="billing-manual-read-only-reason"
                        class="form-control"
                        name="manualReadOnlyReason"
                        rows="3"
                        maxlength="500"
                    >{fromMaybe "" (maybeControl >>= (.manualReadOnlyReason))}</textarea>
                </div>
                <div class="small app-muted">
                    Last changed: {maybe "Never" renderControlAudit maybeControl}
                </div>
                <div>
                    <button type="submit" class="btn btn-outline-primary">Update Controls</button>
                </div>
            </form>
        |]

renderBillingEventsPanel :: [BillingEvent] -> Html
renderBillingEventsPanel events =
    simpleAppPanel
        "Recent Stripe Events"
        (Just "Webhook summaries only. Full Stripe payloads are not stored.")
        ( if null events
            then [hsx|<p class="mb-0 app-muted">No billing events received.</p>|]
            else [hsx|
                    <div class="table-responsive">
                        <table class="table table-sm align-middle mb-0">
                            <thead>
                                <tr>
                                    <th>Received</th>
                                    <th>Type</th>
                                    <th>Status</th>
                                    <th>Object</th>
                                </tr>
                            </thead>
                            <tbody>
                                {forEach events renderBillingEventRow}
                            </tbody>
                        </table>
                    </div>
                |]
        )

renderBillingEventRow :: BillingEvent -> Html
renderBillingEventRow event = [hsx|
    <tr>
        <td class="small">{tshow event.receivedAt}</td>
        <td>{event.eventType}</td>
        <td><span class={eventStatusBadgeClass event.status}>{event.status}</span></td>
        <td class="small app-muted">{renderProviderObject event}</td>
    </tr>
|]

eventStatusBadgeClass :: Text -> Text
eventStatusBadgeClass status =
    "badge " <> case status of
        "processed" -> "text-bg-success"
        "failed"    -> "text-bg-danger"
        "ignored"   -> "text-bg-secondary"
        _           -> "text-bg-secondary"

renderProviderObject :: BillingEvent -> Text
renderProviderObject event =
    Text.intercalate " " (filter (not . Text.null) [fromMaybe "" event.providerObjectType, fromMaybe "" event.providerObjectId])

renderBillingManualReadOnlyToggle :: Bool -> Html
renderBillingManualReadOnlyToggle isReadOnly =
    renderAppToggleButton $
        (defaultAppToggleButtonConfig "billing-manual-read-only" (namedBooleanToggleField "manualReadOnly") isReadOnly [hsx|<span>Manual read-only</span>|])
            { appToggleRoleSwitch = True }

renderControlAudit :: VenueBillingControl -> Text
renderControlAudit control =
    formatMaybeTime control.setAt

formatMaybeTime :: Show value => Maybe value -> Text
formatMaybeTime =
    maybe "Not recorded" tshow

currentVenueName :: (?context :: ControllerContext) => Text
currentVenueName =
    maybe "Current venue" (.name) currentVenueOrNothing

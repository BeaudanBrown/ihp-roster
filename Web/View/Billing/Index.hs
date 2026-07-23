{-# LANGUAGE TypeApplications #-}

module Web.View.Billing.Index where

import Application.Helper.Controller (currentVenueOrNothing)
import qualified Application.Helper.FrontendContract.Surface.Billing as Surface
import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values (noSurfaceFields,
                                                           surfaceFragmentTargetId)
import qualified Data.Text as Text
import Data.Time.Clock (utctDay)
import Web.Billing.FrontendSurface (BillingCheckoutReturnState (..),
                                    billingSurfaceImpl,
                                    currentBillingScopeValue)
import Web.View.Prelude

data BillingViewer
    = BillingOwnerViewer
    | BillingFounderViewer
    deriving (Eq, Show)

data BillingViewModel = BillingViewModel
    { billingViewer            :: !BillingViewer
    , maybeCustomer            :: !(Maybe VenueBillingCustomer)
    , maybeSubscription        :: !(Maybe VenueSubscription)
    , recentCheckoutAttempts   :: ![BillingCheckoutAttempt]
    , recentEvents             :: ![BillingEvent]
    , recentReconciliationJobs :: ![AppJob]
    , checkoutReturn           :: !(Maybe BillingCheckoutReturn)
    , stripeCheckoutAvailable  :: !Bool
    , stripePortalAvailable    :: !Bool
    }

data BillingCheckoutReturn = BillingCheckoutReturn
    { checkoutAttemptId :: !Text
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
            { appPageTitle = billingPageTitle viewModel.billingViewer
            , appPageDescription = billingPageDescription viewModel.billingViewer
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

billingPageTitle :: BillingViewer -> Text
billingPageTitle BillingOwnerViewer   = "Billing"
billingPageTitle BillingFounderViewer = "Billing diagnostics"

billingPageDescription :: BillingViewer -> Maybe Text
billingPageDescription BillingOwnerViewer = Just "Manage this venue's Bepis subscription through Stripe-hosted payment pages."
billingPageDescription BillingFounderViewer = Just "Founder support diagnostics for the current venue. Payment administration remains in Stripe."

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
renderbillingStatusLiveFragment viewModel = [hsx|
    <div id={surfaceFragmentTargetId @Surface.BillingSurface @Surface.BillingStatus noSurfaceFields}>
        {renderBillingAudienceView viewModel}
    </div>
|]

renderBillingAudienceView :: BillingViewModel -> Html
renderBillingAudienceView viewModel@BillingViewModel { billingViewer = BillingOwnerViewer, checkoutReturn } = [hsx|
    <div class="app-page-stack" data-billing-owner-view="true">
        {renderOwnerSubscriptionPanel viewModel}
        {renderBillingCheckoutReturnDialog checkoutReturn}
    </div>
|]
renderBillingAudienceView BillingViewModel
    { billingViewer = BillingFounderViewer
    , maybeCustomer
    , maybeSubscription
    , recentCheckoutAttempts
    , recentEvents
    , recentReconciliationJobs
    } = [hsx|
    <div class="app-page-stack" data-billing-founder-diagnostics="true">
        {renderFounderSubscriptionPanel maybeCustomer maybeSubscription}
        {renderBillingCheckoutAttemptsPanel recentCheckoutAttempts}
        {renderBillingEventsPanel recentEvents}
        {renderBillingReconciliationPanel recentReconciliationJobs}
    </div>
|]

billingCheckoutReturnState :: Maybe BillingCheckoutReturn -> BillingCheckoutReturnState
billingCheckoutReturnState Nothing =
    BillingCheckoutReturnState
        { billingCheckoutReturned = False
        , billingCheckoutAttemptId = Nothing
        , billingCheckoutSessionId = Nothing
        }
billingCheckoutReturnState (Just BillingCheckoutReturn { checkoutAttemptId }) =
    BillingCheckoutReturnState
        { billingCheckoutReturned = True
        , billingCheckoutAttemptId = Just checkoutAttemptId
        , billingCheckoutSessionId = Nothing
        }

renderBillingCheckoutReturnDialog :: Maybe BillingCheckoutReturn -> Html
renderBillingCheckoutReturnDialog Nothing = mempty
renderBillingCheckoutReturnDialog (Just checkoutReturn) =
    renderPageDialogModal (pathTo BillingAction) DialogOverlayConfig
        { dialogOverlayTitle = billingCheckoutDialogTitle checkoutReturn.checkoutOutcome
        , dialogOverlayBody = renderBillingCheckoutDialogBody checkoutReturn.checkoutOutcome
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

renderBillingCheckoutDialogBody :: BillingCheckoutOutcome -> Html
renderBillingCheckoutDialogBody BillingCheckoutPending = [hsx|
    <div class="d-flex gap-3 align-items-start">
        <div class="spinner-border text-primary flex-shrink-0" role="status" aria-label="Loading"></div>
        <div>
            <p class="mb-2">Stripe has returned you to Bepis. We are waiting for secure confirmation of this Checkout.</p>
            <p class="mb-0 app-muted small">This usually takes a few seconds. You can leave this page open; it will update automatically.</p>
        </div>
    </div>
|]
renderBillingCheckoutDialogBody (BillingCheckoutConfirmed _) = [hsx|
    <p class="mb-0">Your subscription is confirmed and this venue's billing status is up to date.</p>
|]
renderBillingCheckoutDialogBody (BillingCheckoutFailed _) = [hsx|
    <p class="mb-2">We could not confirm this Checkout. No subscription has been assumed from the browser return.</p>
    <p class="mb-0 app-muted small">Try again, or contact Bepis support if the problem continues.</p>
|]

data OwnerBillingAction
    = OwnerStartSubscription !Text
    | OwnerOpenBillingPortal !Text
    deriving (Eq, Show)

data OwnerBillingPresentation = OwnerBillingPresentation
    { ownerStateLabel      :: !Text
    , ownerStateBadgeClass :: !Text
    , ownerStateGuidance   :: !Text
    , ownerStateAction     :: !OwnerBillingAction
    }

renderOwnerSubscriptionPanel :: BillingViewModel -> Html
renderOwnerSubscriptionPanel viewModel@BillingViewModel { maybeSubscription } =
    let presentation = ownerBillingPresentation maybeSubscription
     in simpleAppPanel
        "Venue subscription"
        (Just "Bepis costs AUD 100 per venue each month. Payment details stay on Stripe-hosted pages.")
        [hsx|
            <div class="d-flex flex-column gap-4">
                <section aria-label="Subscription status">
                    <span class={"badge " <> presentation.ownerStateBadgeClass}>{presentation.ownerStateLabel}</span>
                    <p class="mb-0 mt-2">{presentation.ownerStateGuidance}</p>
                </section>
                <div class="table-responsive">
                    <table class="table table-sm align-middle mb-0">
                        <tbody>
                            <tr>
                                <th scope="row" class="w-25">Venue</th>
                                <td>{currentVenueName}</td>
                            </tr>
                            <tr>
                                <th scope="row">Plan</th>
                                <td>Bepis venue subscription</td>
                            </tr>
                            <tr>
                                <th scope="row">Price</th>
                                <td>AUD 100/month</td>
                            </tr>
                            <tr>
                                <th scope="row">Current period</th>
                                <td>{renderOwnerBillingPeriod maybeSubscription}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
                {renderOwnerCancellationNotice maybeSubscription}
                <div>
                    {renderOwnerBillingAction viewModel presentation.ownerStateAction}
                </div>
            </div>
        |]

ownerBillingPresentation :: Maybe VenueSubscription -> OwnerBillingPresentation
ownerBillingPresentation Nothing =
    ownerPresentation
        "No subscription"
        "text-bg-secondary"
        "Start a subscription for this venue at AUD 100 per month. Checkout is hosted securely by Stripe."
        (OwnerStartSubscription "Start Subscription")
ownerBillingPresentation (Just subscription)
    | subscription.status == "canceled" =
        ownerPresentation
            "Canceled"
            "text-bg-secondary"
            "This venue's subscription has ended. Restart it whenever you are ready."
            (OwnerStartSubscription "Restart Subscription")
    | subscription.status == "incomplete_expired" =
        ownerPresentation
            "Setup expired"
            "text-bg-secondary"
            "The previous payment setup expired before it was completed. You can start again safely."
            (OwnerStartSubscription "Restart Subscription")
    | subscription.cancelAtPeriodEnd =
        ownerPresentation
            "Cancellation scheduled"
            "text-bg-warning"
            "The subscription remains active for the current period but will not renew."
            (OwnerOpenBillingPortal "Manage Cancellation")
    | subscription.status `elem` ["past_due", "unpaid", "paused", "incomplete"] =
        ownerPresentation
            "Payment needs attention"
            "text-bg-warning"
            "Open Stripe to update your payment method and review the payment that needs attention."
            (OwnerOpenBillingPortal "Resolve Payment")
    | otherwise =
        ownerPresentation
            "Active"
            "text-bg-success"
            "Your subscription is active and renews automatically each month."
            (OwnerOpenBillingPortal "Manage Billing")

ownerPresentation :: Text -> Text -> Text -> OwnerBillingAction -> OwnerBillingPresentation
ownerPresentation ownerStateLabel ownerStateBadgeClass ownerStateGuidance ownerStateAction =
    OwnerBillingPresentation { .. }

renderOwnerBillingPeriod :: Maybe VenueSubscription -> Text
renderOwnerBillingPeriod Nothing = "Starts after subscription confirmation"
renderOwnerBillingPeriod (Just subscription) =
    case (subscription.currentPeriodStart, subscription.currentPeriodEnd) of
        (Just periodStart, Just periodEnd) ->
            formatDateDisplay (utctDay periodStart) <> " – " <> formatDateDisplay (utctDay periodEnd)
        (Nothing, Just periodEnd) -> "Ends " <> formatDateDisplay (utctDay periodEnd)
        (Just periodStart, Nothing) -> "Started " <> formatDateDisplay (utctDay periodStart)
        (Nothing, Nothing) -> "Timing not yet available"

renderOwnerCancellationNotice :: Maybe VenueSubscription -> Html
renderOwnerCancellationNotice (Just subscription)
    | subscription.cancelAtPeriodEnd = [hsx|
        <div class="alert alert-warning mb-0" role="status">
            <strong>Cancellation scheduled.</strong>
            This subscription will not renew after {renderOwnerPeriodEnd subscription.currentPeriodEnd}.
        </div>
    |]
renderOwnerCancellationNotice _ = mempty

renderOwnerPeriodEnd :: Maybe UTCTime -> Text
renderOwnerPeriodEnd =
    maybe "the current billing period" (formatDateDisplay . utctDay)

renderOwnerBillingAction :: BillingViewModel -> OwnerBillingAction -> Html
renderOwnerBillingAction BillingViewModel { stripeCheckoutAvailable } (OwnerStartSubscription label) =
    renderOwnerBillingActionForm
        (pathTo CreateBillingCheckoutSessionAction)
        label
        stripeCheckoutAvailable
        renderCheckoutUnavailableNotice
renderOwnerBillingAction BillingViewModel { stripePortalAvailable } (OwnerOpenBillingPortal label) =
    renderOwnerBillingActionForm
        (pathTo CreateBillingPortalSessionAction)
        label
        stripePortalAvailable
        renderPortalUnavailableNotice

renderOwnerBillingActionForm :: Text -> Text -> Bool -> Html -> Html
renderOwnerBillingActionForm actionUrl label available unavailableNotice = [hsx|
    <div class="d-flex flex-column align-items-start gap-2">
        <form method="POST" action={actionUrl}>
            <button type="submit" class="btn btn-primary" disabled={not available}>{label}</button>
        </form>
        {if available then renderPaymentStepUpNotice else unavailableNotice}
    </div>
|]

renderPaymentStepUpNotice :: Html
renderPaymentStepUpNotice = [hsx|
    <p class="mb-0 app-muted small">You will verify with your passkey before Stripe opens.</p>
|]

renderCheckoutUnavailableNotice :: Html
renderCheckoutUnavailableNotice = [hsx|
    <p class="mb-0 app-muted small">New subscriptions are temporarily unavailable. Please try again later.</p>
|]

renderPortalUnavailableNotice :: Html
renderPortalUnavailableNotice = [hsx|
    <p class="mb-0 app-muted small">Billing management is temporarily unavailable. Please contact Bepis support if you need help.</p>
|]

renderFounderSubscriptionPanel :: Maybe VenueBillingCustomer -> Maybe VenueSubscription -> Html
renderFounderSubscriptionPanel maybeCustomer maybeSubscription =
    simpleAppPanel
        "Provider snapshot"
        (Just "Bounded Stripe identifiers and local mirror state for founder support. Payment details are never stored here.")
        [hsx|
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <tbody>
                        <tr>
                            <th scope="row" class="w-25">Venue</th>
                            <td>{currentVenueName}</td>
                        </tr>
                        <tr>
                            <th scope="row">Mode</th>
                            <td>{founderProviderMode maybeCustomer maybeSubscription}</td>
                        </tr>
                        <tr>
                            <th scope="row">Customer ID</th>
                            <td class="small app-muted">{maybe "Not recorded" (boundedIdentifier . (.stripeCustomerId)) maybeCustomer}</td>
                        </tr>
                        <tr>
                            <th scope="row">Subscription ID</th>
                            <td class="small app-muted">{maybe "Not recorded" (boundedIdentifier . (.stripeSubscriptionId)) maybeSubscription}</td>
                        </tr>
                        <tr>
                            <th scope="row">Price ID</th>
                            <td class="small app-muted">{maybe "Not recorded" (boundedIdentifier . (.stripePriceId)) maybeSubscription}</td>
                        </tr>
                        <tr>
                            <th scope="row">Provider status</th>
                            <td>{maybe "No local subscription" (.status) maybeSubscription}</td>
                        </tr>
                        <tr>
                            <th scope="row">Current period</th>
                            <td>{renderOwnerBillingPeriod maybeSubscription}</td>
                        </tr>
                        <tr>
                            <th scope="row">Cancellation at period end</th>
                            <td>{maybe "Not recorded" (yesNo . (.cancelAtPeriodEnd)) maybeSubscription}</td>
                        </tr>
                        <tr>
                            <th scope="row">Last synchronized</th>
                            <td>{maybe "Not recorded" (formatUtcTimestamp . (.lastSyncedAt)) maybeSubscription}</td>
                        </tr>
                        <tr>
                            <th scope="row">Last provider event</th>
                            <td class="small app-muted">{maybe "Not recorded" (maybe "Not recorded" boundedIdentifier . (.lastAppliedStripeEventId)) maybeSubscription}</td>
                        </tr>
                    </tbody>
                </table>
            </div>
        |]

founderProviderMode :: Maybe VenueBillingCustomer -> Maybe VenueSubscription -> Text
founderProviderMode maybeCustomer maybeSubscription =
    case maybeSubscription of
        Just subscription -> providerModeText subscription.livemode
        Nothing -> maybe "Not recorded" (providerModeText . (.livemode)) maybeCustomer

providerModeText :: Bool -> Text
providerModeText True  = "live"
providerModeText False = "test"

yesNo :: Bool -> Text
yesNo True  = "Yes"
yesNo False = "No"

renderBillingCheckoutAttemptsPanel :: [BillingCheckoutAttempt] -> Html
renderBillingCheckoutAttemptsPanel attempts =
    simpleAppPanel
        "Recent Checkout attempts"
        (Just "Known local attempts only. Identifiers and failure summaries are bounded before display.")
        ( if null attempts
            then [hsx|<p class="mb-0 app-muted">No Checkout attempts recorded for this venue.</p>|]
            else [hsx|
                <div class="table-responsive">
                    <table class="table table-sm align-middle mb-0">
                        <thead>
                            <tr>
                                <th>Created</th>
                                <th>Status</th>
                                <th>Attempt</th>
                                <th>Checkout Session</th>
                                <th>Subscription</th>
                                <th>Failure</th>
                            </tr>
                        </thead>
                        <tbody>{forEach attempts renderBillingCheckoutAttemptRow}</tbody>
                    </table>
                </div>
            |]
        )

renderBillingCheckoutAttemptRow :: BillingCheckoutAttempt -> Html
renderBillingCheckoutAttemptRow attempt = [hsx|
    <tr>
        <td class="small">{formatUtcTimestamp attempt.createdAt}</td>
        <td><span class={billingAttemptStatusBadgeClass attempt.status}>{boundedIdentifier attempt.status}</span></td>
        <td class="small app-muted">{boundedIdentifier (inputValue attempt.id)}</td>
        <td class="small app-muted">{maybe "Not recorded" boundedIdentifier attempt.stripeCheckoutSessionId}</td>
        <td class="small app-muted">{maybe "Not recorded" boundedIdentifier attempt.stripeSubscriptionId}</td>
        <td class="small text-danger">{billingCheckoutAttemptFailure attempt}</td>
    </tr>
|]

billingAttemptStatusBadgeClass :: Text -> Text
billingAttemptStatusBadgeClass status =
    "badge " <> case status of
        "completed" -> "text-bg-success"
        "failed"    -> "text-bg-danger"
        "expired"   -> "text-bg-secondary"
        _           -> "text-bg-warning"

billingCheckoutAttemptFailure :: BillingCheckoutAttempt -> Text
billingCheckoutAttemptFailure attempt =
    case catMaybes [attempt.errorCode, attempt.errorSummary] of
        []           -> ""
        failureParts -> boundedDiagnostic (Text.intercalate ": " failureParts)

renderBillingReconciliationPanel :: [AppJob] -> Html
renderBillingReconciliationPanel jobs =
    simpleAppPanel
        "Stripe synchronization"
        (Just "Queue a read-only refresh of this venue's known Stripe state. Synchronization never creates a subscription or changes venue writability.")
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
            <td class="small">{formatUtcTimestamp appJob.createdAt}</td>
            <td><span class={presentation.statusBadgeClass}>{presentation.statusLabel}</span></td>
            <td class="small app-muted">{boundedIdentifier (inputValue appJob.id)}</td>
            <td class="small text-danger">{reconciliationDiagnostic appJob}</td>
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

reconciliationDiagnostic :: AppJob -> Text
reconciliationDiagnostic appJob
    | inputValue appJob.status `elem` ["job_status_retry", "job_status_failed", "job_status_timed_out"] =
        maybe "No diagnostic recorded." boundedDiagnostic appJob.lastError
    | otherwise = ""

renderBillingEventsPanel :: [BillingEvent] -> Html
renderBillingEventsPanel events =
    simpleAppPanel
        "Recent Stripe events"
        (Just "Bounded webhook summaries only. Full Stripe payloads are not stored.")
        ( if null events
            then [hsx|<p class="mb-0 app-muted">No billing events received.</p>|]
            else [hsx|
                <div class="table-responsive">
                    <table class="table table-sm align-middle mb-0">
                        <thead>
                            <tr>
                                <th>Received</th>
                                <th>Event</th>
                                <th>Type</th>
                                <th>Status</th>
                                <th>Object</th>
                                <th>Summary</th>
                            </tr>
                        </thead>
                        <tbody>{forEach events renderBillingEventRow}</tbody>
                    </table>
                </div>
            |]
        )

renderBillingEventRow :: BillingEvent -> Html
renderBillingEventRow event = [hsx|
    <tr>
        <td class="small">{formatUtcTimestamp event.receivedAt}</td>
        <td class="small app-muted">{boundedIdentifier event.stripeEventId}</td>
        <td>{boundedIdentifier event.eventType}</td>
        <td><span class={eventStatusBadgeClass event.status}>{boundedIdentifier event.status}</span></td>
        <td class="small app-muted">{renderProviderObject event}</td>
        <td class="small text-danger">{maybe "" boundedDiagnostic event.errorSummary}</td>
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
    boundedIdentifier $
        Text.intercalate " " $
            filter (not . Text.null)
                [ fromMaybe "" event.providerObjectType
                , fromMaybe "" event.providerObjectId
                ]

boundedIdentifier :: Text -> Text
boundedIdentifier = Text.take 255

boundedDiagnostic :: Text -> Text
boundedDiagnostic = Text.take 1000

currentVenueName :: (?context :: ControllerContext) => Text
currentVenueName =
    maybe "Current venue" (.name) currentVenueOrNothing

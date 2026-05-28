module Web.View.Billing.Index where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.LiveSurface (liveSurfaceConfigJson, mkTypedDefinedLiveSurface)
import qualified Data.Text as Text
import Web.Billing.LiveUpdates
import Web.View.Prelude

data BillingViewModel = BillingViewModel
    { maybeCustomer     :: !(Maybe VenueBillingCustomer)
    , maybeSubscription :: !(Maybe VenueSubscription)
    , maybeControl      :: !(Maybe VenueBillingControl)
    , recentEvents      :: ![BillingEvent]
    }

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
            , appPageWidthClass = ""
            , appPageBody = [hsx|
                <div id="billing-live-surface"
                     class="app-page-stack"
                     data-live-update-surface={liveSurfaceConfigJson (mkTypedDefinedLiveSurface billingLiveSurfaceDefinition currentBillingSurfaceKey)}>
                    {renderBillingStatusFragment viewModel}
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
            "No subscription change was recorded. You can start Checkout again from the billing page."

renderBillingResultPage :: Text -> Text -> Html
renderBillingResultPage title message =
    renderAppPage AppPageConfig
        { appPageTitle = title
        , appPageDescription = Nothing
        , appPageActions = [hsx|<a class="btn btn-outline-secondary" href={BillingAction}>Back to Billing</a>|]
        , appPageWidthClass = "app-form-width"
        , appPageBody =
            simpleAppPanel title Nothing [hsx|
                <p class="mb-0 app-muted">{message}</p>
            |]
        }

renderBillingStatusFragment :: BillingViewModel -> Html
renderBillingStatusFragment viewModel@BillingViewModel { recentEvents, maybeControl } = [hsx|
    <div id="billing-status-fragment">
        {renderBillingStatusPanel viewModel}
        {if currentUserIsSupportAdmin then renderBillingControlPanel maybeControl else mempty}
        {renderBillingEventsPanel recentEvents}
    </div>
|]

renderBillingStatusPanel :: BillingViewModel -> Html
renderBillingStatusPanel BillingViewModel { maybeCustomer, maybeSubscription } =
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
                    <form method="POST" action={CreateBillingCheckoutSessionAction} data-disable-javascript-submission="true">
                        <button type="submit" class="btn btn-primary">Start Subscription</button>
                    </form>
                    <form method="POST" action={CreateBillingPortalSessionAction} data-disable-javascript-submission="true">
                        <button type="submit" class="btn btn-outline-primary" disabled={isNothing maybeCustomer}>Manage Billing</button>
                    </form>
                </div>
            </div>
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

renderBillingControlPanel :: Maybe VenueBillingControl -> Html
renderBillingControlPanel maybeControl =
    simpleAppPanel
        "Manual Controls"
        (Just "Founder support can mark a venue read-only manually. Stripe status does not change this flag in v1.")
        [hsx|
            <form method="POST" action={UpdateVenueBillingControlAction} class="d-flex flex-column gap-3" data-disable-javascript-submission="true">
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
        _           -> "text-bg-light"

renderProviderObject :: BillingEvent -> Text
renderProviderObject event =
    Text.intercalate " " (filter (not . Text.null) [fromMaybe "" event.providerObjectType, fromMaybe "" event.providerObjectId])

renderBillingManualReadOnlyToggle :: Bool -> Html
renderBillingManualReadOnlyToggle isReadOnly =
    renderAppToggleButton $ (defaultAppToggleButtonConfig "billing-manual-read-only" isReadOnly [hsx|<span>Manual read-only</span>|])
        { appToggleInputName = Just "manualReadOnly"
        , appToggleInputValue = "true"
        , appToggleRoleSwitch = True
        }

renderControlAudit :: VenueBillingControl -> Text
renderControlAudit control =
    formatMaybeTime control.setAt

formatMaybeTime :: Show value => Maybe value -> Text
formatMaybeTime =
    maybe "Not recorded" tshow

currentVenueName :: (?context :: ControllerContext) => Text
currentVenueName =
    maybe "Current venue" (.name) currentVenueOrNothing

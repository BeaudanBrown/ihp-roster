module Web.Controller.Billing where

import Application.Billing.Stripe
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.Url (appendQueryParams)
import Control.Monad (guard, void)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Web.Billing.Mutations
import Web.Controller.Prelude
import Web.View.Billing.Index

instance Controller BillingController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenue
        ensureProfileCompleted
        ensureBillingAccess

    action currentAction@BillingAction = runBepis currentAction BepisPageAction do
        viewModel <- fetchBillingViewModel
        render BillingView { .. }

    action currentAction@ShowbillingStatusLiveFragmentAction = runBepis currentAction BepisFragmentAction do
        viewModel <- fetchBillingViewModel
        respondHtml (renderbillingStatusLiveFragment viewModel)

    action currentAction@CreateBillingCheckoutSessionAction = runBepis currentAction BepisMutationAction $
        createBillingCheckoutSessionAction

    action currentAction@CreateBillingPortalSessionAction = runBepis currentAction BepisMutationAction $
        createBillingPortalSessionAction

    action currentAction@BillingSuccessAction = runBepis currentAction BepisPageAction do
        let checkoutParams = ("checkout", "success") : maybe [] (\sessionId -> [("session_id", sessionId)]) (paramOrNothing @Text "session_id")
        redirectToPath (appendQueryParams (pathTo BillingAction) checkoutParams)

    action currentAction@BillingCancelAction = runBepis currentAction BepisPageAction $
        render BillingCancelView

    action currentAction@UpdateVenueBillingControlAction = runBepis currentAction BepisMutationAction $
        updateVenueBillingControlAction

ensureBillingAccess :: (?context :: ControllerContext, ?request :: Request, ?modelContext :: ModelContext) => IO ()
ensureBillingAccess = do
    redirectPermissionDeniedUnless
        (currentUserIsSuperAdmin || hasRole VenueOwnerRole)
        "Only the venue owner or a super admin can manage billing for this venue."
    ensurePrivilegedPasskeyReady

fetchBillingViewModel :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO BillingViewModel
fetchBillingViewModel = do
    maybeCustomer <- fetchCurrentVenueBillingCustomer
    maybeSubscription <- fetchCurrentVenueSubscription
    maybeControl <- fetchCurrentVenueBillingControl
    recentEvents <-
        query @BillingEvent
            |> filterWhere (#venueId, Just (unpackId currentVenueId))
            |> orderByDesc #receivedAt
            |> limit 5
            |> fetch
    let checkoutReturn = billingCheckoutReturnFromRequest maybeSubscription recentEvents
    pure BillingViewModel { .. }

billingCheckoutReturnFromRequest :: (?request :: Request) => Maybe VenueSubscription -> [BillingEvent] -> Maybe BillingCheckoutReturn
billingCheckoutReturnFromRequest maybeSubscription recentEvents = do
    guard (paramOrNothing @Text "checkout" == Just "success" || isJust checkoutSessionId)
    pure BillingCheckoutReturn
        { checkoutSessionId
        , checkoutOutcome = classifyCheckoutOutcome checkoutSessionId maybeSubscription recentEvents
        }
    where
        checkoutSessionId = paramOrNothing @Text "session_id"

classifyCheckoutOutcome :: Maybe Text -> Maybe VenueSubscription -> [BillingEvent] -> BillingCheckoutOutcome
classifyCheckoutOutcome _ (Just subscription) _ = BillingCheckoutConfirmed subscription
classifyCheckoutOutcome checkoutSessionId Nothing recentEvents =
    maybe
        BillingCheckoutPending
        BillingCheckoutFailed
        (find (isCheckoutFailure checkoutSessionId) recentEvents)

isCheckoutFailure :: Maybe Text -> BillingEvent -> Bool
isCheckoutFailure checkoutSessionId event =
    event.status == "failed"
        || (event.eventType == "checkout.session.async_payment_failed" && maybe True (\sessionId -> event.providerObjectId == Just sessionId) checkoutSessionId)

fetchCurrentVenueBillingCustomer :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Maybe VenueBillingCustomer)
fetchCurrentVenueBillingCustomer =
    query @VenueBillingCustomer
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOneOrNothing

fetchCurrentVenueSubscription :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Maybe VenueSubscription)
fetchCurrentVenueSubscription =
    query @VenueSubscription
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOneOrNothing

fetchCurrentVenueBillingControl :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Maybe VenueBillingControl)
fetchCurrentVenueBillingControl =
    query @VenueBillingControl
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOneOrNothing

createBillingCheckoutSessionAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
createBillingCheckoutSessionAction =
    readStripeConfig >>= \case
        Left message -> billingRedirectWithError message
        Right stripeConfig -> do
            stripeClient <- currentStripeClient
            resolveBillingPrice stripeClient stripeConfig >>= \case
                Left message -> billingRedirectWithError message
                Right price ->
                    ensureVenueStripeCustomer stripeClient stripeConfig >>= \case
                        Left message -> billingRedirectWithError message
                        Right billingCustomer -> do
                            let venueIdText = inputValue currentVenueId
                            let successUrl = stripeConfig.appBaseUrl <> pathTo BillingSuccessAction <> "?session_id={CHECKOUT_SESSION_ID}"
                            let cancelUrl = stripeConfig.appBaseUrl <> pathTo BillingCancelAction
                            checkoutResult <-
                                stripeClient.createCheckoutSession
                                    stripeConfig
                                    venueIdText
                                    billingCustomer.stripeCustomerId
                                    price.stripePriceId
                                    successUrl
                                    cancelUrl
                            case checkoutResult of
                                Left err -> billingRedirectWithError ("Stripe Checkout failed: " <> stripeClientErrorText err)
                                Right checkoutSession ->
                                    case checkoutSession.stripeCheckoutSessionUrl of
                                        Nothing -> billingRedirectWithError "Stripe Checkout did not return a hosted session URL."
                                        Just checkoutUrl -> do
                                            void $ recordCurrentUserAuditEvent
                                                "billing_checkout_started"
                                                "venue_billing_customers"
                                                (unpackId billingCustomer.id)
                                                (Aeson.object
                                                    [ "stripeCustomerId" Aeson..= billingCustomer.stripeCustomerId
                                                    , "stripeCheckoutSessionId" Aeson..= checkoutSession.stripeCheckoutSessionId
                                                    , "stripePriceId" Aeson..= price.stripePriceId
                                                    ])
                                            redirectToBillingUrl checkoutUrl

createBillingPortalSessionAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
createBillingPortalSessionAction =
    readStripeConfig >>= \case
        Left message -> billingRedirectWithError message
        Right stripeConfig -> do
            maybeCustomer <- fetchCurrentVenueBillingCustomer
            case maybeCustomer of
                Nothing -> billingRedirectWithError "Start a subscription before opening the billing portal."
                Just billingCustomer -> do
                    stripeClient <- currentStripeClient
                    let returnUrl = stripeConfig.appBaseUrl <> pathTo BillingAction
                    portalResult <-
                        stripeClient.createPortalSession
                            stripeConfig
                            (inputValue currentVenueId)
                            billingCustomer.stripeCustomerId
                            returnUrl
                    case portalResult of
                        Left err -> billingRedirectWithError ("Stripe Customer Portal failed: " <> stripeClientErrorText err)
                        Right portalSession -> do
                            void $ recordCurrentUserAuditEvent
                                "billing_portal_started"
                                "venue_billing_customers"
                                (unpackId billingCustomer.id)
                                (Aeson.object
                                    [ "stripeCustomerId" Aeson..= billingCustomer.stripeCustomerId
                                    , "stripePortalSessionId" Aeson..= portalSession.stripePortalSessionId
                                    ])
                            redirectToBillingUrl portalSession.stripePortalSessionUrl

resolveBillingPrice :: StripeClient -> StripeConfig -> IO (Either Text StripePrice)
resolveBillingPrice stripeClient stripeConfig =
    case stripeConfig.priceId of
        Just configuredPriceId -> do
            priceResult <- stripeClient.retrievePrice stripeConfig configuredPriceId
            pure (firstStripeError priceResult >>= validateVenueMonthlyPrice)
        Nothing -> do
            pricesResult <- stripeClient.listPrices stripeConfig
            pure case pricesResult of
                Left err -> Left ("Stripe Price lookup failed: " <> stripeClientErrorText err)
                Right [price] -> validateVenueMonthlyPrice price
                Right [] -> Left "Stripe Price lookup did not return an active monthly AUD 100 price."
                Right _ -> Left "Stripe Price lookup returned multiple prices for the configured lookup key."

firstStripeError :: Either StripeClientError value -> Either Text value
firstStripeError = \case
    Left err -> Left (stripeClientErrorText err)
    Right value -> Right value

ensureVenueStripeCustomer :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => StripeClient -> StripeConfig -> IO (Either Text VenueBillingCustomer)
ensureVenueStripeCustomer stripeClient stripeConfig = do
    fetchCurrentVenueBillingCustomer >>= \case
        Just customer -> pure (Right customer)
        Nothing -> do
            customerResult <- stripeClient.createCustomer stripeConfig (inputValue currentVenueId) currentVenue.name
            case customerResult of
                Left err -> pure (Left ("Stripe Customer create failed: " <> stripeClientErrorText err))
                Right stripeCustomer -> do
                    mutationResult <- createVenueBillingCustomerMutation stripeCustomer.stripeCustomerId
                    pure (Right mutationResult.liveMutationValue)

updateVenueBillingControlAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
updateVenueBillingControlAction = do
    redirectPermissionDeniedUnless currentUserIsSuperAdmin "Only super admins can update billing controls."
    let manualReadOnly = paramOrDefault @Text "false" "manualReadOnly" == "true"
    let reason = Text.strip (paramOrDefault @Text "" "manualReadOnlyReason")
    if manualReadOnly && Text.null reason
        then billingRedirectWithError "A reason is required when manual read-only is enabled."
        else if Text.length reason > 500
            then billingRedirectWithError "Manual read-only reason must be 500 characters or fewer."
            else do
                now <- getCurrentTime
                _ <- updateVenueBillingControlMutation manualReadOnly reason now
                setSuccessMessage "Billing controls updated."
                redirectTo BillingAction

billingRedirectWithError :: (?context :: ControllerContext, ?request :: Request) => Text -> IO ()
billingRedirectWithError message = do
    setErrorMessage message
    redirectTo BillingAction

redirectToBillingUrl :: (?context :: ControllerContext, ?request :: Request) => Text -> IO ()
redirectToBillingUrl url =
    if isHtmxRequest
        then do
            setHeader ("HX-Redirect", cs url)
            renderPlain ""
        else redirectToUrl url

module Web.Controller.Billing where

import Application.Async.Queue (EnqueueAppJobResult (..))
import Application.Billing.Checkout
import Application.Billing.Reconciliation
import Application.Billing.Stripe
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.Url (appendQueryParams)
import Control.Monad (guard, void)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
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

    action currentAction@CreateBillingCheckoutSessionAction = runBepis currentAction BepisMutationAction do
        ensureOwnerBillingPaymentAction
        when (isNothing currentUser.emailVerifiedAt) do
            billingRedirectWithError "Verify your account email before starting Checkout."
        createBillingCheckoutSessionAction

    action currentAction@CreateBillingPortalSessionAction = runBepis currentAction BepisMutationAction do
        ensureOwnerBillingPaymentAction
        createBillingPortalSessionAction

    action currentAction@BillingSuccessAction = runBepis currentAction BepisPageAction do
        fetchCorrelatedCheckoutReturnAttempt >>= \case
            Nothing -> billingRedirectWithError "That Checkout return does not match this venue."
            Just attempt -> do
                void (enqueueBillingCheckoutReconciliation (Just (unpackId currentUser.id)) attempt)
                redirectToPath $
                    appendQueryParams
                        (pathTo BillingAction)
                        [ ("checkout", "success")
                        , ("attempt_id", inputValue attempt.id)
                        ]

    action currentAction@BillingCancelAction = runBepis currentAction BepisPageAction do
        fetchCorrelatedCheckoutCancelAttempt >>= \case
            Nothing -> billingRedirectWithError "That Checkout cancellation does not match this venue."
            Just _ -> render BillingCancelView

    action currentAction@ReconcileVenueBillingAction = runBepis currentAction BepisMutationAction do
        ensureFounderBillingReconciliationAction
        enqueueVenueBillingReconciliation (Just (unpackId currentUser.id)) currentVenue >>= \case
            Left failure -> billingRedirectWithError failure.reconciliationFailureSummary
            Right enqueueResult -> do
                let (appJob, alreadyActive) = case enqueueResult of
                        EnqueuedAppJob job       -> (job, False)
                        ExistingActiveAppJob job -> (job, True)
                void $ recordCurrentUserAuditEvent
                    "billing_reconciliation_requested"
                    "app_jobs"
                    (unpackId appJob.id)
                    ( Aeson.object
                        [ "alreadyActive" Aeson..= alreadyActive
                        , "relatedTable" Aeson..= appJob.relatedTable
                        , "relatedId" Aeson..= appJob.relatedId
                        ]
                    )
                setSuccessMessage $
                    if alreadyActive
                        then "Billing synchronization is already queued."
                        else "Billing synchronization queued."
                redirectTo BillingAction

    action currentAction@UpdateVenueBillingControlAction = runBepis currentAction BepisMutationAction $
        updateVenueBillingControlAction

ensureBillingAccess :: (?context :: ControllerContext, ?request :: Request, ?modelContext :: ModelContext) => IO ()
ensureBillingAccess = do
    redirectPermissionDeniedUnless
        (currentUserIsSuperAdmin || hasRole VenueOwnerRole)
        "Only the venue owner or a super admin can manage billing for this venue."
    if currentUserIsSuperAdmin
        then ensureFreshPasskeyReady
        else ensurePrivilegedPasskeySetupComplete

ensureOwnerBillingPaymentAction :: (?context :: ControllerContext, ?request :: Request, ?modelContext :: ModelContext) => IO ()
ensureOwnerBillingPaymentAction = do
    redirectPermissionDeniedUnless
        (not currentUserIsSuperAdmin && hasRole VenueOwnerRole)
        "Only the venue owner can start Checkout or open Customer Portal."
    ensureFreshPasskeyReady

ensureFounderBillingReconciliationAction :: (?context :: ControllerContext, ?request :: Request, ?modelContext :: ModelContext) => IO ()
ensureFounderBillingReconciliationAction = do
    redirectPermissionDeniedUnless
        currentUserIsSuperAdmin
        "Only super admins can synchronize venue billing."
    ensureFreshPasskeyReady

fetchBillingViewModel :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO BillingViewModel
fetchBillingViewModel = do
    maybeCustomer <- fetchCurrentVenueBillingCustomer
    maybeSubscription <- fetchCurrentVenueSubscription
    let billingViewer =
            if currentUserIsSuperAdmin
                then BillingFounderViewer
                else BillingOwnerViewer
    recentCheckoutAttempts <-
        if currentUserIsSuperAdmin
            then
                query @BillingCheckoutAttempt
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> orderByDesc #createdAt
                    |> limit 5
                    |> fetch
            else pure []
    recentEvents <-
        if currentUserIsSuperAdmin
            then
                query @BillingEvent
                    |> filterWhere (#venueId, Just (unpackId currentVenueId))
                    |> orderByDesc #receivedAt
                    |> limit 5
                    |> fetch
            else pure []
    recentReconciliationJobs <-
        if currentUserIsSuperAdmin
            then
                query @AppJob
                    |> filterWhere (#venueId, Just (unpackId currentVenueId))
                    |> filterWhere (#jobKind, billingReconciliationJobKind)
                    |> orderByDesc #createdAt
                    |> limit 5
                    |> fetch
            else pure []
    stripeConfig <- readStripeConfig
    let stripeCheckoutAvailable =
            either (const False) (.stripeDeploymentControls.stripeCheckoutEnabled) stripeConfig
                && checkoutAllowedForSubscription maybeSubscription
    let stripePortalAvailable =
            case stripeConfig of
                Right _ -> isJust maybeCustomer
                Left _  -> False
    checkoutReturn <-
        if currentUserIsSuperAdmin
            then pure Nothing
            else fetchBillingCheckoutReturn maybeSubscription
    pure BillingViewModel { .. }

fetchBillingCheckoutReturn
    :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request)
    => Maybe VenueSubscription
    -> IO (Maybe BillingCheckoutReturn)
fetchBillingCheckoutReturn maybeSubscription
    | paramOrNothing @Text "checkout" /= Just "success" = pure Nothing
    | otherwise =
        fetchBillingCheckoutProgressAttempt >>= \case
            Nothing -> pure Nothing
            Just attempt -> do
                maybeCompletionEvent <- fetchExactCheckoutCompletionEvent attempt
                pure $ Just BillingCheckoutReturn
                    { checkoutAttemptId = inputValue attempt.id
                    , checkoutOutcome = classifyCheckoutOutcome attempt maybeCompletionEvent maybeSubscription
                    }

fetchExactCheckoutCompletionEvent
    :: (?context :: ControllerContext, ?modelContext :: ModelContext)
    => BillingCheckoutAttempt
    -> IO (Maybe BillingEvent)
fetchExactCheckoutCompletionEvent attempt =
    query @BillingEvent
        |> filterWhere (#venueId, Just (unpackId currentVenueId))
        |> filterWhere (#livemode, attempt.livemode)
        |> filterWhere (#providerObjectType, Just "checkout.session")
        |> filterWhere (#providerObjectId, attempt.stripeCheckoutSessionId)
        |> filterWhere (#stripeCustomerId, Just attempt.stripeCustomerId)
        |> filterWhere (#status, "processed")
        |> filterWhereIn (#eventType, ["checkout.session.completed", "checkout.session.async_payment_succeeded"])
        |> orderByDesc #stripeCreatedAt
        |> fetchOneOrNothing

classifyCheckoutOutcome :: BillingCheckoutAttempt -> Maybe BillingEvent -> Maybe VenueSubscription -> BillingCheckoutOutcome
classifyCheckoutOutcome attempt maybeCompletionEvent maybeSubscription
    | Just subscription <- matchingConfirmedSubscription attempt maybeCompletionEvent maybeSubscription =
        BillingCheckoutConfirmed subscription
    | attempt.status == "failed" = BillingCheckoutFailed attempt
    | otherwise = BillingCheckoutPending

matchingConfirmedSubscription
    :: BillingCheckoutAttempt
    -> Maybe BillingEvent
    -> Maybe VenueSubscription
    -> Maybe VenueSubscription
matchingConfirmedSubscription attempt maybeCompletionEvent maybeSubscription = do
    subscription <- maybeSubscription
    let attemptMatches =
            attempt.status == "completed"
                && attempt.stripeSubscriptionId == Just subscription.stripeSubscriptionId
    let eventMatches =
            maybe False
                (\event -> event.stripeSubscriptionId == Just subscription.stripeSubscriptionId)
                maybeCompletionEvent
    guard (attemptMatches || eventMatches)
    pure subscription

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

fetchCorrelatedCheckoutReturnAttempt :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (Maybe BillingCheckoutAttempt)
fetchCorrelatedCheckoutReturnAttempt =
    case (paramOrNothing @Text "attempt_id" >>= parseUUIDText, paramOrNothing @Text "session_id") of
        (Just attemptId, Just sessionId) ->
            query @BillingCheckoutAttempt
                |> filterWhere (#id, Id attemptId)
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#stripeCheckoutSessionId, Just sessionId)
                |> fetchOneOrNothing
        _ -> pure Nothing

fetchBillingCheckoutProgressAttempt :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (Maybe BillingCheckoutAttempt)
fetchBillingCheckoutProgressAttempt =
    case paramOrNothing @Text "attempt_id" >>= parseUUIDText of
        Nothing -> pure Nothing
        Just attemptId ->
            query @BillingCheckoutAttempt
                |> filterWhere (#id, Id attemptId)
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereNot (#stripeCheckoutSessionId, Nothing)
                |> fetchOneOrNothing

fetchCorrelatedCheckoutCancelAttempt :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (Maybe BillingCheckoutAttempt)
fetchCorrelatedCheckoutCancelAttempt =
    case paramOrNothing @Text "attempt_id" >>= parseUUIDText of
        Nothing -> pure Nothing
        Just attemptId -> do
            maybeAttempt <-
                query @BillingCheckoutAttempt
                    |> filterWhere (#id, Id attemptId)
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> fetchOneOrNothing
            pure do
                attempt <- maybeAttempt
                storedSessionId <- attempt.stripeCheckoutSessionId
                case paramOrNothing @Text "session_id" of
                    Just suppliedSessionId | suppliedSessionId /= storedSessionId -> Nothing
                    _ -> Just attempt

createBillingCheckoutSessionAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
createBillingCheckoutSessionAction =
    readStripeConfig >>= \case
        Left message -> billingRedirectWithError message
        Right stripeConfig ->
            if stripeConfig.stripeDeploymentControls.stripeCheckoutEnabled
                then createEnabledBillingCheckoutSession stripeConfig
                else billingRedirectWithError "Starting a new subscription is temporarily unavailable. Existing billing management remains available."

createEnabledBillingCheckoutSession :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => StripeConfig -> IO ()
createEnabledBillingCheckoutSession stripeConfig = do
    stripeClient <- currentStripeClient
    let successUrlFor attemptId =
            appendQueryParams
                (stripeConfig.appBaseUrl <> pathTo BillingSuccessAction)
                [("attempt_id", inputValue attemptId)]
                <> "&session_id={CHECKOUT_SESSION_ID}"
    -- Stripe documents Session substitution for success_url, not cancel_url.
    -- Cancellation therefore carries the opaque attempt ID and is accepted only
    -- when that current-venue attempt already has a stored Session ID.
    let cancelUrlFor attemptId =
            appendQueryParams
                (stripeConfig.appBaseUrl <> pathTo BillingCancelAction)
                [("attempt_id", inputValue attemptId)]
    checkoutResult <-
        startOrResumeBillingCheckoutMutation
            stripeClient
            stripeConfig
            currentVenue
            currentUser
            successUrlFor
            cancelUrlFor
    case checkoutResult.liveMutationValue.checkoutStartOutcome of
        CheckoutStartRejected message -> billingRedirectWithError message
        CheckoutAwaitingWebhook attempt -> redirectToCorrelatedCheckoutReturn attempt
        CheckoutSessionReady attempt checkoutSession ->
            case checkoutSession.stripeCheckoutSessionUrl of
                Nothing -> billingRedirectWithError "Stripe Checkout did not return a hosted session URL."
                Just checkoutUrl ->
                    validateStripeCheckoutRedirectUrl checkoutUrl >>= \case
                        Left message -> billingRedirectWithError message
                        Right validatedCheckoutUrl -> do
                            void $ recordCurrentUserAuditEvent
                                "billing_checkout_started"
                                "billing_checkout_attempts"
                                (unpackId attempt.id)
                                (Aeson.object
                                    [ "stripeCustomerId" Aeson..= attempt.stripeCustomerId
                                    , "stripeCheckoutSessionId" Aeson..= checkoutSession.stripeCheckoutSessionId
                                    , "stripePriceId" Aeson..= attempt.stripePriceId
                                    , "resumed" Aeson..= not checkoutResult.liveMutationValue.checkoutAttemptWasCreated
                                    ])
                            redirectToBillingUrl validatedCheckoutUrl

redirectToCorrelatedCheckoutReturn :: (?context :: ControllerContext, ?request :: Request) => BillingCheckoutAttempt -> IO ()
redirectToCorrelatedCheckoutReturn attempt =
    case attempt.stripeCheckoutSessionId of
        Nothing -> billingRedirectWithError "The open Checkout attempt has no Stripe Session to resume."
        Just _ ->
            redirectToPath $
                appendQueryParams
                    (pathTo BillingAction)
                    [ ("checkout", "success")
                    , ("attempt_id", inputValue attempt.id)
                    ]

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
                    portalRequestId <- UUID.toText <$> UUIDv4.nextRandom
                    portalResult <-
                        stripeClient.createPortalSession
                            stripeConfig
                            portalRequestId
                            (inputValue currentVenueId)
                            billingCustomer.stripeCustomerId
                            returnUrl
                    case portalResult of
                        Left err -> billingRedirectWithError ("Stripe Customer Portal failed: " <> stripeClientErrorText err)
                        Right portalSession ->
                            case validateCreatedPortalSession billingCustomer.stripeCustomerId returnUrl portalSession of
                                Left message -> billingRedirectWithError message
                                Right validatedPortalSession ->
                                    validateStripePortalRedirectUrl validatedPortalSession.stripePortalSessionUrl >>= \case
                                        Left message -> billingRedirectWithError message
                                        Right validatedPortalUrl -> do
                                            void $ recordCurrentUserAuditEvent
                                                "billing_portal_started"
                                                "venue_billing_customers"
                                                (unpackId billingCustomer.id)
                                                (Aeson.object
                                                    [ "stripeCustomerId" Aeson..= billingCustomer.stripeCustomerId
                                                    , "stripePortalSessionId" Aeson..= validatedPortalSession.stripePortalSessionId
                                                    ])
                                            redirectToBillingUrl validatedPortalUrl

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

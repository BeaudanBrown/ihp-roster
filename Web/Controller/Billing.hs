module Web.Controller.Billing where

import Application.Billing.Checkout
import Application.Billing.Stripe
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.Url (appendQueryParams)
import Control.Monad (void)
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
            Just attempt ->
                redirectToPath $
                    appendQueryParams
                        (pathTo BillingAction)
                        [ ("checkout", "success")
                        , ("attempt_id", inputValue attempt.id)
                        , ("session_id", fromMaybe "" attempt.stripeCheckoutSessionId)
                        ]

    action currentAction@BillingCancelAction = runBepis currentAction BepisPageAction do
        fetchCorrelatedCheckoutCancelAttempt >>= \case
            Nothing -> billingRedirectWithError "That Checkout cancellation does not match this venue."
            Just _ -> render BillingCancelView

    action currentAction@UpdateVenueBillingControlAction = runBepis currentAction BepisMutationAction $
        updateVenueBillingControlAction

ensureBillingAccess :: (?context :: ControllerContext, ?request :: Request, ?modelContext :: ModelContext) => IO ()
ensureBillingAccess = do
    redirectPermissionDeniedUnless
        (currentUserIsSuperAdmin || hasRole VenueOwnerRole)
        "Only the venue owner or a super admin can manage billing for this venue."
    ensurePrivilegedPasskeyReady

ensureOwnerBillingPaymentAction :: (?context :: ControllerContext, ?request :: Request, ?modelContext :: ModelContext) => IO ()
ensureOwnerBillingPaymentAction = do
    redirectPermissionDeniedUnless
        (not currentUserIsSuperAdmin && hasRole VenueOwnerRole)
        "Only the venue owner can start Checkout or open Customer Portal."
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
    stripeControls <- readStripeDeploymentControls
    let stripeCheckoutAvailable =
            either (const False) (.stripeCheckoutEnabled) stripeControls
                && checkoutAllowedForSubscription maybeSubscription
    checkoutReturn <- fetchBillingCheckoutReturn maybeSubscription
    pure BillingViewModel { .. }

fetchBillingCheckoutReturn
    :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request)
    => Maybe VenueSubscription
    -> IO (Maybe BillingCheckoutReturn)
fetchBillingCheckoutReturn maybeSubscription
    | paramOrNothing @Text "checkout" /= Just "success" = pure Nothing
    | otherwise =
        fmap (fmap \attempt ->
            BillingCheckoutReturn
                { checkoutAttemptId = inputValue attempt.id
                , checkoutSessionId = attempt.stripeCheckoutSessionId
                , checkoutOutcome = classifyCheckoutOutcome attempt maybeSubscription
                }) fetchCorrelatedCheckoutReturnAttempt

classifyCheckoutOutcome :: BillingCheckoutAttempt -> Maybe VenueSubscription -> BillingCheckoutOutcome
classifyCheckoutOutcome attempt maybeSubscription
    | attempt.status == "completed"
    , Just attemptSubscriptionId <- attempt.stripeSubscriptionId
    , Just subscription <- maybeSubscription
    , subscription.stripeSubscriptionId == attemptSubscriptionId =
        BillingCheckoutConfirmed subscription
    | attempt.status == "failed" = BillingCheckoutFailed attempt
    | otherwise = BillingCheckoutPending

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
        Just sessionId ->
            redirectToPath $
                appendQueryParams
                    (pathTo BillingAction)
                    [ ("checkout", "success")
                    , ("attempt_id", inputValue attempt.id)
                    , ("session_id", sessionId)
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

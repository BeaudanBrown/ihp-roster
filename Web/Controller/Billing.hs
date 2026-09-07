module Web.Controller.Billing where

import Application.Billing.Reconciliation
import Application.Billing.Stripe
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.Url (appendQueryParams)
import Control.Monad (void)
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import Web.Billing.Mutations
import Web.Billing.ReadModel
import Web.Billing.Responses
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
        when (isNothing effectiveCurrentUser.emailVerifiedAt) do
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
                redirectToCorrelatedCheckoutReturn attempt

    action currentAction@BillingCancelAction = runBepis currentAction BepisPageAction do
        fetchCorrelatedCheckoutCancelAttempt >>= \case
            Nothing -> billingRedirectWithError "That Checkout cancellation does not match this venue."
            Just _ -> render BillingCancelView

    action currentAction@ReconcileVenueBillingAction = runBepis currentAction BepisMutationAction do
        ensureFounderBillingReconciliationAction
        enqueueVenueBillingReconciliation (Just (unpackId currentUser.id)) currentVenue
            >>= respondWithBillingReconciliation

    action currentAction@UpdateVenueBillingControlAction = runBepis currentAction BepisMutationAction $
        updateVenueBillingControlAction

ensureBillingAccess :: (?context :: ControllerContext, ?request :: Request, ?modelContext :: ModelContext) => IO ()
ensureBillingAccess = do
    redirectPermissionDeniedUnless
        (currentUserIsUnimpersonatedSuperAdmin || hasRole VenueOwner)
        "Only the venue owner or a super admin can manage billing for this venue."
    if currentUserIsUnimpersonatedSuperAdmin
        then ensurePrivilegedPasskeyReady
        else ensurePrivilegedPasskeySetupComplete

ensureOwnerBillingPaymentAction :: (?context :: ControllerContext, ?request :: Request, ?modelContext :: ModelContext) => IO ()
ensureOwnerBillingPaymentAction = do
    redirectPermissionDeniedUnless
        (not currentUserIsUnimpersonatedSuperAdmin && hasRole VenueOwner)
        "Only the venue owner can start Checkout or open Customer Portal."
    ensurePrivilegedPasskeyReady

ensureFounderBillingReconciliationAction :: (?context :: ControllerContext, ?request :: Request, ?modelContext :: ModelContext) => IO ()
ensureFounderBillingReconciliationAction = do
    redirectPermissionDeniedUnless
        currentUserIsUnimpersonatedSuperAdmin
        "Only super admins can synchronize venue billing."
    ensurePrivilegedPasskeyReady

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
            actualAuthenticatedUser
            effectiveRequestUser
            successUrlFor
            cancelUrlFor
    respondWithBillingCheckout checkoutResult.liveMutationValue

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
                    respondWithBillingPortal billingCustomer returnUrl portalResult

updateVenueBillingControlAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
updateVenueBillingControlAction = do
    redirectPermissionDeniedUnless currentUserIsUnimpersonatedSuperAdmin "Only super admins can update billing controls."
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

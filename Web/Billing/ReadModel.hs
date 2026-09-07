module Web.Billing.ReadModel
    ( fetchBillingViewModel
    , fetchCurrentVenueBillingCustomer
    , fetchCorrelatedCheckoutReturnAttempt
    , fetchCorrelatedCheckoutCancelAttempt
    ) where

import Application.Billing.Checkout (checkoutAllowedForSubscription)
import Application.Billing.Reconciliation (billingReconciliationJobKind)
import Application.Billing.Stripe (StripeConfig (..),
                                   StripeDeploymentControls (..),
                                   readStripeConfig)
import Control.Monad (guard)
import Web.Controller.Prelude
import Web.View.Billing.Index (BillingCheckoutOutcome (..),
                               BillingCheckoutReturn (..),
                               BillingViewModel (..), BillingViewer (..))

-- Call only after the shared Billing access policy. Audience selection retains
-- the distinction between unimpersonated support and an effective venue owner.
fetchBillingViewModel :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO BillingViewModel
fetchBillingViewModel = do
    maybeCustomer <- fetchCurrentVenueBillingCustomer
    maybeSubscription <- fetchCurrentVenueSubscription
    let billingViewer =
            if currentUserIsUnimpersonatedSuperAdmin
                then BillingFounderViewer
                else BillingOwnerViewer
    recentCheckoutAttempts <-
        if currentUserIsUnimpersonatedSuperAdmin
            then
                query @BillingCheckoutAttempt
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> orderByDesc #createdAt
                    |> limit 5
                    |> fetch
            else pure []
    recentEvents <-
        if currentUserIsUnimpersonatedSuperAdmin
            then
                query @BillingEvent
                    |> filterWhere (#venueId, Just (unpackId currentVenueId))
                    |> orderByDesc #receivedAt
                    |> limit 5
                    |> fetch
            else pure []
    recentReconciliationJobs <-
        if currentUserIsUnimpersonatedSuperAdmin
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
        if currentUserIsUnimpersonatedSuperAdmin
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
    | attempt.status `elem` ["failed", "expired"] = BillingCheckoutFailed attempt
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

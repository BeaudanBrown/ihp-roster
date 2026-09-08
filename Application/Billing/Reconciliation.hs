module Application.Billing.Reconciliation
    ( BillingReconciliationFailure (..)
    , BillingReconciliationOutcome (..)
    , BillingReconciliationSweepSummary (..)
    , billingReconciliationJobKind
    , enqueueBillingCheckoutReconciliation
    , enqueueBillingReconciliationSweep
    , enqueueBillingSubscriptionReconciliation
    , enqueueVenueBillingReconciliation
    , performBillingReconciliationJob
    , reconcileKnownCheckoutAttempt
    , reconcileKnownSubscription
    )
where

import Application.Async.Boundary (throwAppJobError, trySynchronousAppJobAction)
import Application.Async.Error (AppJobError (..))
import Application.Async.Queue
import Application.Billing.Persistence (lockVenueForBilling)
import Application.Billing.Stripe
import Application.Helper.FrontendContract.Surface.Billing.Resource (billingResource)
import Application.Helper.SurfaceResource (SurfaceResourceValue,
                                           liveMutationResult)
import qualified Control.Exception as Exception
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Generated.Types
import IHP.ControllerPrelude
import Application.Helper.LiveUpdate.BackgroundMutation (withDurableLiveMutationOutcomeWithoutContext,
                                withDurableLiveMutationWithoutContext)

data BillingReconciliationFailure = BillingReconciliationFailure
    { reconciliationFailureCode    :: !Text
    , reconciliationFailureSummary :: !Text
    }
    deriving (Eq, Show)

data BillingReconciliationOutcome
    = BillingSubscriptionReconciled !VenueSubscription
    | BillingCheckoutStillPending !BillingCheckoutAttempt
    | BillingCheckoutExpired !BillingCheckoutAttempt
    deriving (Eq, Show)

data BillingReconciliationSweepSummary = BillingReconciliationSweepSummary
    { eligibleSubscriptionCount :: !Int
    , enqueuedJobCount          :: !Int
    , existingJobCount          :: !Int
    }
    deriving (Eq, Show)

billingReconciliationJobKind :: Text
billingReconciliationJobKind = "billing_reconciliation"

-- | Reconcile only a Checkout attempt already known to Bepis. This boundary
-- performs read-only Stripe API calls; it never creates a provider Customer,
-- Checkout Session, Price, or Subscription.
reconcileKnownCheckoutAttempt
    :: (?modelContext :: ModelContext)
    => StripeClient
    -> StripeConfig
    -> BillingCheckoutAttempt
    -> IO (Either BillingReconciliationFailure BillingReconciliationOutcome)
reconcileKnownCheckoutAttempt stripeClient stripeConfig attempt = do
    observedAt <- getCurrentTime
    venue <- fetch (Id attempt.venueId :: Id Venue)
    case validateAttemptMode stripeConfig attempt of
        Left failure -> pure (Left failure)
        Right () ->
            case attempt.stripeCheckoutSessionId of
                Nothing -> pure (Left (reconciliationFailure "checkout_session_missing" "The known Checkout attempt has no Stripe Checkout Session."))
                Just sessionId ->
                    stripeClient.retrieveCheckoutSession stripeConfig sessionId attempt.stripeCustomerId >>= \case
                        Left _ -> pure (Left (reconciliationFailure "checkout_session_retrieve_failed" "The Stripe Checkout Session could not be retrieved for reconciliation."))
                        Right checkoutSession ->
                            case validateCheckoutSession venue attempt checkoutSession of
                                Left failure -> pure (Left failure)
                                Right () -> reconcileCheckoutSession stripeClient stripeConfig observedAt venue attempt checkoutSession

validateAttemptMode :: StripeConfig -> BillingCheckoutAttempt -> Either BillingReconciliationFailure ()
validateAttemptMode stripeConfig attempt =
    unless (attempt.livemode == stripeModeIsLive stripeConfig.stripeMode) $
        Left (reconciliationFailure "checkout_mode_mismatch" "The known Checkout attempt belongs to a different Stripe mode.")

validateCheckoutSession :: Venue -> BillingCheckoutAttempt -> StripeCheckoutSession -> Either BillingReconciliationFailure ()
validateCheckoutSession venue attempt checkoutSession = do
    unless (checkoutSession.stripeCheckoutSessionId == fromMaybe "" attempt.stripeCheckoutSessionId) $
        Left (reconciliationFailure "checkout_session_mismatch" "Stripe returned a different Checkout Session during reconciliation.")
    unless (checkoutSession.stripeCheckoutCustomerId == Just attempt.stripeCustomerId) $
        Left (reconciliationFailure "checkout_customer_mismatch" "The Stripe Checkout Session Customer does not match the known Checkout attempt.")
    unless (checkoutSession.stripeCheckoutLivemode == attempt.livemode) $
        Left (reconciliationFailure "checkout_mode_mismatch" "The Stripe Checkout Session belongs to a different Stripe mode.")
    unless (checkoutSession.stripeCheckoutMode == "subscription") $
        Left (reconciliationFailure "checkout_mode_invalid" "The Stripe Checkout Session is not a subscription Checkout.")
    unless (checkoutSession.stripeCheckoutClientReferenceId == Just venueIdText) $
        Left (reconciliationFailure "checkout_venue_mismatch" "The Stripe Checkout Session client reference does not match this venue.")
    unless (checkoutSession.stripeCheckoutVenueId == Just venueIdText) $
        Left (reconciliationFailure "checkout_metadata_mismatch" "The Stripe Checkout Session venue metadata does not match this venue.")
    unless (checkoutSession.stripeCheckoutStatus `elem` ["open", "complete", "expired"]) $
        Left (reconciliationFailure "checkout_status_invalid" "The Stripe Checkout Session has an unsupported reconciliation status.")
  where
    venueIdText = inputValue venue.id

reconcileCheckoutSession
    :: (?modelContext :: ModelContext)
    => StripeClient
    -> StripeConfig
    -> UTCTime
    -> Venue
    -> BillingCheckoutAttempt
    -> StripeCheckoutSession
    -> IO (Either BillingReconciliationFailure BillingReconciliationOutcome)
reconcileCheckoutSession stripeClient stripeConfig observedAt venue attempt checkoutSession =
    case checkoutSession.stripeCheckoutStatus of
        "open" -> updateNonCompleteCheckoutAttempt venue attempt checkoutSession False
        "expired" -> updateNonCompleteCheckoutAttempt venue attempt checkoutSession True
        "complete" ->
            case checkoutSession.stripeCheckoutSubscriptionId of
                Nothing -> pure (Left (reconciliationFailure "checkout_subscription_missing" "The completed Stripe Checkout Session has no Subscription."))
                Just subscriptionId ->
                    stripeClient.retrieveSubscription stripeConfig subscriptionId >>= \case
                        Left _ -> pure (Left (reconciliationFailure "subscription_retrieve_failed" "The Stripe Subscription could not be retrieved for reconciliation."))
                        Right subscription ->
                            case validateSubscription venue attempt subscriptionId subscription of
                                Left failure -> pure (Left failure)
                                Right () -> applyCheckoutSubscription observedAt venue attempt checkoutSession subscription
        _ -> pure (Left (reconciliationFailure "checkout_status_invalid" "The Stripe Checkout Session has an unsupported reconciliation status."))

updateNonCompleteCheckoutAttempt
    :: (?modelContext :: ModelContext)
    => Venue
    -> BillingCheckoutAttempt
    -> StripeCheckoutSession
    -> Bool
    -> IO (Either BillingReconciliationFailure BillingReconciliationOutcome)
updateNonCompleteCheckoutAttempt venue attempt checkoutSession isExpired =
    withDurableLiveMutationOutcomeWithoutContext (billingReconciliationPublication "billing.reconciliation.checkout") do
        lockVenueForBilling (unpackId venue.id)
        fetchOneOrNothing attempt.id >>= \case
            Nothing -> pure (Left (reconciliationFailure "checkout_attempt_missing" "The known Checkout attempt no longer exists."))
            Just currentAttempt ->
                case validateCurrentAttempt attempt currentAttempt of
                    Left failure -> pure (Left failure)
                    Right () -> do
                        updatedAttempt <-
                            currentAttempt
                                |> set #status (if isExpired then "expired" else "open")
                                |> set #expiresAt (Just (checkoutExpiresAt checkoutSession))
                                |> set #completedAt Nothing
                                |> set #errorCode Nothing
                                |> set #errorSummary Nothing
                                |> updateRecord
                        pure $ Right $
                            if isExpired
                                then BillingCheckoutExpired updatedAttempt
                                else BillingCheckoutStillPending updatedAttempt

validateSubscription
    :: Venue
    -> BillingCheckoutAttempt
    -> Text
    -> StripeSubscription
    -> Either BillingReconciliationFailure ()
validateSubscription venue attempt expectedSubscriptionId subscription = do
    validateSubscriptionSnapshot venue expectedSubscriptionId attempt.livemode subscription
    unless (subscription.stripeSubscriptionCustomerId == attempt.stripeCustomerId) $
        Left (reconciliationFailure "subscription_customer_mismatch" "The Stripe Subscription Customer does not match the known Checkout attempt.")

validateSubscriptionSnapshot
    :: Venue
    -> Text
    -> Bool
    -> StripeSubscription
    -> Either BillingReconciliationFailure ()
validateSubscriptionSnapshot venue expectedSubscriptionId expectedLivemode subscription = do
    unless (subscription.stripeSubscriptionId == expectedSubscriptionId) $
        Left (reconciliationFailure "subscription_id_mismatch" "Stripe returned a different Subscription during reconciliation.")
    unless (subscription.stripeSubscriptionVenueId == Just (inputValue venue.id)) $
        Left (reconciliationFailure "subscription_metadata_mismatch" "The Stripe Subscription venue metadata does not match this venue.")
    unless (subscription.stripeSubscriptionLivemode == expectedLivemode) $
        Left (reconciliationFailure "subscription_mode_mismatch" "The Stripe Subscription belongs to a different Stripe mode.")
    unless (subscription.stripeSubscriptionPriceLivemode == expectedLivemode) $
        Left (reconciliationFailure "subscription_price_mode_mismatch" "The Stripe Subscription Price belongs to a different Stripe mode.")
    unless (subscription.stripeSubscriptionStatus `elem` supportedSubscriptionStatuses) $
        Left (reconciliationFailure "subscription_status_invalid" "The Stripe Subscription has an unsupported status.")
    unless (subscription.stripeSubscriptionCurrentPeriodStart <= subscription.stripeSubscriptionCurrentPeriodEnd) $
        Left (reconciliationFailure "subscription_period_invalid" "The Stripe Subscription Item period is invalid.")

-- | Refresh a Subscription row that Bepis already knows. Unlike Checkout
-- reconciliation, this path can only update that existing local mirror.
reconcileKnownSubscription
    :: (?modelContext :: ModelContext)
    => StripeClient
    -> StripeConfig
    -> VenueSubscription
    -> IO (Either BillingReconciliationFailure BillingReconciliationOutcome)
reconcileKnownSubscription stripeClient stripeConfig subscription = do
    observedAt <- getCurrentTime
    venue <- fetch (Id subscription.venueId :: Id Venue)
    if subscription.livemode /= stripeModeIsLive stripeConfig.stripeMode
        then pure (Left (reconciliationFailure "subscription_mode_mismatch" "The known Subscription belongs to a different Stripe mode."))
        else
            stripeClient.retrieveSubscription stripeConfig subscription.stripeSubscriptionId >>= \case
                Left _ -> pure (Left (reconciliationFailure "subscription_retrieve_failed" "The Stripe Subscription could not be retrieved for reconciliation."))
                Right stripeSubscription ->
                    case validateSubscriptionSnapshot venue subscription.stripeSubscriptionId subscription.livemode stripeSubscription of
                        Left failure -> pure (Left failure)
                        Right () -> applyKnownSubscription observedAt venue subscription stripeSubscription

applyKnownSubscription
    :: (?modelContext :: ModelContext)
    => UTCTime
    -> Venue
    -> VenueSubscription
    -> StripeSubscription
    -> IO (Either BillingReconciliationFailure BillingReconciliationOutcome)
applyKnownSubscription observedAt venue expectedSubscription stripeSubscription =
    withDurableLiveMutationOutcomeWithoutContext (billingReconciliationPublication "billing.reconciliation.subscription") do
        lockVenueForBilling (unpackId venue.id)
        maybeCurrentSubscription <- fetchOneOrNothing expectedSubscription.id
        maybeVenueCustomer <-
            query @VenueBillingCustomer
                |> filterWhere (#venueId, unpackId venue.id)
                |> fetchOneOrNothing
        maybeProviderCustomer <-
            query @VenueBillingCustomer
                |> filterWhere (#stripeCustomerId, stripeSubscription.stripeSubscriptionCustomerId)
                |> fetchOneOrNothing
        let localState = KnownSubscriptionLocalState
                { currentKnownSubscription = maybeCurrentSubscription
                , currentKnownVenueCustomer = maybeVenueCustomer
                , currentKnownProviderCustomer = maybeProviderCustomer
                }
        case validateKnownSubscriptionLocalState observedAt expectedSubscription stripeSubscription localState of
            Left failure -> pure (Left failure)
            Right currentSubscription -> do
                _ <- ensureLocalCustomer venue stripeSubscription maybeVenueCustomer
                reconciledAt <- getCurrentTime
                reconciledSubscription <- upsertLocalSubscription observedAt reconciledAt venue stripeSubscription (Just currentSubscription)
                pure (Right (BillingSubscriptionReconciled reconciledSubscription))

data KnownSubscriptionLocalState = KnownSubscriptionLocalState
    { currentKnownSubscription     :: !(Maybe VenueSubscription)
    , currentKnownVenueCustomer    :: !(Maybe VenueBillingCustomer)
    , currentKnownProviderCustomer :: !(Maybe VenueBillingCustomer)
    }

validateKnownSubscriptionLocalState
    :: UTCTime
    -> VenueSubscription
    -> StripeSubscription
    -> KnownSubscriptionLocalState
    -> Either BillingReconciliationFailure VenueSubscription
validateKnownSubscriptionLocalState observedAt expectedSubscription stripeSubscription localState = do
    currentSubscription <- maybe (Left (reconciliationFailure "local_subscription_missing" "The known local Subscription no longer exists.")) Right localState.currentKnownSubscription
    unless (currentSubscription.venueId == expectedSubscription.venueId) $
        Left (reconciliationFailure "local_subscription_venue_changed" "The known local Subscription venue changed during reconciliation.")
    unless (currentSubscription.stripeSubscriptionId == expectedSubscription.stripeSubscriptionId) $
        Left (reconciliationFailure "local_subscription_id_changed" "The known local Stripe Subscription changed during reconciliation.")
    unless (currentSubscription.livemode == expectedSubscription.livemode) $
        Left (reconciliationFailure "local_subscription_mode_changed" "The known local Subscription mode changed during reconciliation.")
    unless
        ( currentSubscription.lastAppliedStripeEventCreatedAt == expectedSubscription.lastAppliedStripeEventCreatedAt
            && currentSubscription.lastAppliedStripeEventId == expectedSubscription.lastAppliedStripeEventId
        ) $
        Left (reconciliationFailure "local_subscription_advanced" "The local Subscription advanced while reconciliation was reading Stripe.")
    forM_ currentSubscription.lastAppliedStripeEventCreatedAt \appliedAt ->
        when (appliedAt > addUTCTime (-1) observedAt) $
            Left (reconciliationFailure "local_subscription_advanced" "The local Subscription is newer than the reconciliation observation boundary.")
    validateCustomerAssociation
        currentSubscription.venueId
        stripeSubscription
        localState.currentKnownVenueCustomer
        localState.currentKnownProviderCustomer
    pure currentSubscription

applyCheckoutSubscription
    :: (?modelContext :: ModelContext)
    => UTCTime
    -> Venue
    -> BillingCheckoutAttempt
    -> StripeCheckoutSession
    -> StripeSubscription
    -> IO (Either BillingReconciliationFailure BillingReconciliationOutcome)
applyCheckoutSubscription observedAt venue attempt checkoutSession stripeSubscription =
    withDurableLiveMutationOutcomeWithoutContext (billingReconciliationPublication "billing.reconciliation.checkout_subscription") do
        lockVenueForBilling (unpackId venue.id)
        maybeCurrentAttempt <- fetchOneOrNothing attempt.id
        maybeVenueCustomer <-
            query @VenueBillingCustomer
                |> filterWhere (#venueId, unpackId venue.id)
                |> fetchOneOrNothing
        maybeProviderCustomer <-
            query @VenueBillingCustomer
                |> filterWhere (#stripeCustomerId, stripeSubscription.stripeSubscriptionCustomerId)
                |> fetchOneOrNothing
        maybeVenueSubscription <-
            query @VenueSubscription
                |> filterWhere (#venueId, unpackId venue.id)
                |> fetchOneOrNothing
        maybeProviderSubscription <-
            query @VenueSubscription
                |> filterWhere (#stripeSubscriptionId, stripeSubscription.stripeSubscriptionId)
                |> fetchOneOrNothing
        let localState = CheckoutReconciliationLocalState
                { currentCheckoutAttempt = maybeCurrentAttempt
                , currentCheckoutVenueCustomer = maybeVenueCustomer
                , currentCheckoutProviderCustomer = maybeProviderCustomer
                , currentCheckoutVenueSubscription = maybeVenueSubscription
                , currentCheckoutProviderSubscription = maybeProviderSubscription
                }
        case validateLocalState observedAt attempt stripeSubscription localState of
            Left failure -> pure (Left failure)
            Right currentAttempt -> do
                _ <- ensureLocalCustomer venue stripeSubscription maybeVenueCustomer
                reconciledAt <- getCurrentTime
                subscription <- upsertLocalSubscription observedAt reconciledAt venue stripeSubscription maybeVenueSubscription
                _ <-
                    currentAttempt
                        |> set #stripeSubscriptionId (Just stripeSubscription.stripeSubscriptionId)
                        |> set #status "completed"
                        |> set #expiresAt (Just (checkoutExpiresAt checkoutSession))
                        |> set #completedAt (Just reconciledAt)
                        |> set #errorCode Nothing
                        |> set #errorSummary Nothing
                        |> updateRecord
                pure (Right (BillingSubscriptionReconciled subscription))

data CheckoutReconciliationLocalState = CheckoutReconciliationLocalState
    { currentCheckoutAttempt              :: !(Maybe BillingCheckoutAttempt)
    , currentCheckoutVenueCustomer        :: !(Maybe VenueBillingCustomer)
    , currentCheckoutProviderCustomer     :: !(Maybe VenueBillingCustomer)
    , currentCheckoutVenueSubscription    :: !(Maybe VenueSubscription)
    , currentCheckoutProviderSubscription :: !(Maybe VenueSubscription)
    }

validateLocalState
    :: UTCTime
    -> BillingCheckoutAttempt
    -> StripeSubscription
    -> CheckoutReconciliationLocalState
    -> Either BillingReconciliationFailure BillingCheckoutAttempt
validateLocalState observedAt expectedAttempt stripeSubscription localState = do
    currentAttempt <- maybe (Left (reconciliationFailure "checkout_attempt_missing" "The known Checkout attempt no longer exists.")) Right localState.currentCheckoutAttempt
    validateCurrentAttempt expectedAttempt currentAttempt
    validateCustomerAssociation
        currentAttempt.venueId
        stripeSubscription
        localState.currentCheckoutVenueCustomer
        localState.currentCheckoutProviderCustomer
    case localState.currentCheckoutVenueSubscription of
        Just subscription -> do
            unless (subscription.stripeSubscriptionId == stripeSubscription.stripeSubscriptionId) $
                Left (reconciliationFailure "local_subscription_mismatch" "This venue already has a different Stripe Subscription.")
            unless (subscription.livemode == stripeSubscription.stripeSubscriptionLivemode) $
                Left (reconciliationFailure "local_subscription_mode_mismatch" "This venue's Stripe Subscription belongs to a different mode.")
            forM_ subscription.lastAppliedStripeEventCreatedAt \appliedAt ->
                when (appliedAt > addUTCTime (-1) observedAt) $
                    Left (reconciliationFailure "local_subscription_advanced" "The local Subscription advanced while reconciliation was reading Stripe.")
        Nothing ->
            forM_ localState.currentCheckoutProviderSubscription \subscription ->
                unless (subscription.venueId == currentAttempt.venueId) $
                    Left (reconciliationFailure "provider_subscription_already_associated" "The Stripe Subscription is already associated with another venue.")
    pure currentAttempt

validateCustomerAssociation
    :: UUID
    -> StripeSubscription
    -> Maybe VenueBillingCustomer
    -> Maybe VenueBillingCustomer
    -> Either BillingReconciliationFailure ()
validateCustomerAssociation venueId stripeSubscription maybeVenueCustomer maybeProviderCustomer =
    case maybeVenueCustomer of
        Just customer -> do
            unless (customer.stripeCustomerId == stripeSubscription.stripeSubscriptionCustomerId) $
                Left (reconciliationFailure "local_customer_mismatch" "This venue is associated with a different Stripe Customer.")
            unless (customer.livemode == stripeSubscription.stripeSubscriptionLivemode) $
                Left (reconciliationFailure "local_customer_mode_mismatch" "This venue's Stripe Customer belongs to a different mode.")
        Nothing ->
            forM_ maybeProviderCustomer \customer ->
                unless (customer.venueId == venueId) $
                    Left (reconciliationFailure "provider_customer_already_associated" "The Stripe Customer is already associated with another venue.")

validateCurrentAttempt :: BillingCheckoutAttempt -> BillingCheckoutAttempt -> Either BillingReconciliationFailure ()
validateCurrentAttempt expectedAttempt currentAttempt = do
    unless (currentAttempt.venueId == expectedAttempt.venueId) $
        Left (reconciliationFailure "checkout_attempt_venue_changed" "The known Checkout attempt venue changed during reconciliation.")
    unless (currentAttempt.stripeCheckoutSessionId == expectedAttempt.stripeCheckoutSessionId) $
        Left (reconciliationFailure "checkout_attempt_session_changed" "The known Checkout Session changed during reconciliation.")
    unless (currentAttempt.stripeCustomerId == expectedAttempt.stripeCustomerId) $
        Left (reconciliationFailure "checkout_attempt_customer_changed" "The known Checkout Customer changed during reconciliation.")
    unless (currentAttempt.livemode == expectedAttempt.livemode) $
        Left (reconciliationFailure "checkout_attempt_mode_changed" "The known Checkout mode changed during reconciliation.")
    unless (currentAttempt.status == expectedAttempt.status) $
        Left (reconciliationFailure "checkout_attempt_advanced" "The known Checkout attempt advanced while reconciliation was reading Stripe.")
    unless (currentAttempt.stripeSubscriptionId == expectedAttempt.stripeSubscriptionId) $
        Left (reconciliationFailure "checkout_attempt_advanced" "The known Checkout attempt advanced while reconciliation was reading Stripe.")

ensureLocalCustomer
    :: (?modelContext :: ModelContext)
    => Venue
    -> StripeSubscription
    -> Maybe VenueBillingCustomer
    -> IO VenueBillingCustomer
ensureLocalCustomer venue stripeSubscription = \case
    Just customer -> pure customer
    Nothing ->
        newRecord @VenueBillingCustomer
            |> set #venueId (unpackId venue.id)
            |> set #stripeCustomerId stripeSubscription.stripeSubscriptionCustomerId
            |> set #livemode stripeSubscription.stripeSubscriptionLivemode
            |> createRecord

upsertLocalSubscription
    :: (?modelContext :: ModelContext)
    => UTCTime
    -> UTCTime
    -> Venue
    -> StripeSubscription
    -> Maybe VenueSubscription
    -> IO VenueSubscription
upsertLocalSubscription observedAt reconciledAt venue stripeSubscription maybeExisting =
    case maybeExisting of
        Nothing ->
            newRecord @VenueSubscription
                |> setSubscriptionSnapshot
                |> set #venueId (unpackId venue.id)
                |> set #lastAppliedStripeEventCreatedAt (Just reconciliationCursorAt)
                |> set #lastAppliedStripeEventId (Just reconciliationCursorId)
                |> createRecord
        Just existing ->
            existing
                |> setSubscriptionSnapshot
                |> setOrderingCursor
                |> updateRecord
  where
    setSubscriptionSnapshot record =
        record
            |> set #stripeSubscriptionId stripeSubscription.stripeSubscriptionId
            |> set #stripePriceId stripeSubscription.stripeSubscriptionPriceId
            |> set #livemode stripeSubscription.stripeSubscriptionLivemode
            |> set #status stripeSubscription.stripeSubscriptionStatus
            |> set #currentPeriodStart (Just (stripePeriodTime stripeSubscription.stripeSubscriptionCurrentPeriodStart))
            |> set #currentPeriodEnd (Just (stripePeriodTime stripeSubscription.stripeSubscriptionCurrentPeriodEnd))
            |> set #cancelAtPeriodEnd stripeSubscription.stripeSubscriptionCancelAtPeriodEnd
            |> set #lastSyncedAt reconciledAt
    setOrderingCursor record =
        record
            |> set #lastAppliedStripeEventCreatedAt (Just reconciliationCursorAt)
            |> set #lastAppliedStripeEventId (Just reconciliationCursorId)
    reconciliationCursorAt = addUTCTime (-1) observedAt
    reconciliationCursorId = Text.take 255 ("~billing-reconciliation:checkout:" <> inputValue venue.id)

data BillingReconciliationTarget
    = ReconcileCheckoutAttempt !(Id BillingCheckoutAttempt)
    | ReconcileSubscription !(Id VenueSubscription)

data PersistedBillingReconciliationTarget = PersistedBillingReconciliationTarget
    { payloadTarget        :: !Text
    , payloadLocalRecordId :: !UUID
    }

instance Aeson.FromJSON PersistedBillingReconciliationTarget where
    parseJSON = Aeson.withObject "PersistedBillingReconciliationTarget" \object ->
        PersistedBillingReconciliationTarget
            <$> object Aeson..: "target"
            <*> object Aeson..: "localRecordId"

nonTerminalSubscriptionStatuses :: [Text]
nonTerminalSubscriptionStatuses =
    [ "incomplete"
    , "trialing"
    , "active"
    , "past_due"
    , "unpaid"
    , "paused"
    ]

enqueueBillingReconciliationSweep
    :: (?modelContext :: ModelContext)
    => IO BillingReconciliationSweepSummary
enqueueBillingReconciliationSweep = do
    subscriptions <-
        query @VenueSubscription
            |> filterWhereIn (#status, nonTerminalSubscriptionStatuses)
            |> fetch
    results <- mapM (enqueueBillingSubscriptionReconciliation Nothing) subscriptions
    pure BillingReconciliationSweepSummary
        { eligibleSubscriptionCount = length subscriptions
        , enqueuedJobCount = length [() | EnqueuedAppJob _ <- results]
        , existingJobCount = length [() | ExistingActiveAppJob _ <- results]
        }

enqueueBillingSubscriptionReconciliation
    :: (?modelContext :: ModelContext)
    => Maybe UUID
    -> VenueSubscription
    -> IO EnqueueAppJobResult
enqueueBillingSubscriptionReconciliation requestedByUserId subscription =
    enqueueBillingReconciliationTarget
        requestedByUserId
        subscription.venueId
        "venue_subscriptions"
        (unpackId subscription.id)
        (ReconcileSubscription subscription.id)

enqueueBillingCheckoutReconciliation
    :: (?modelContext :: ModelContext)
    => Maybe UUID
    -> BillingCheckoutAttempt
    -> IO EnqueueAppJobResult
enqueueBillingCheckoutReconciliation requestedByUserId attempt =
    enqueueBillingReconciliationTarget
        requestedByUserId
        attempt.venueId
        "billing_checkout_attempts"
        (unpackId attempt.id)
        (ReconcileCheckoutAttempt attempt.id)

enqueueVenueBillingReconciliation
    :: (?modelContext :: ModelContext)
    => Maybe UUID
    -> Venue
    -> IO (Either BillingReconciliationFailure EnqueueAppJobResult)
enqueueVenueBillingReconciliation requestedByUserId venue =
    query @VenueSubscription
        |> filterWhere (#venueId, unpackId venue.id)
        |> fetchOneOrNothing
        >>= \case
            Just subscription -> Right <$> enqueueBillingSubscriptionReconciliation requestedByUserId subscription
            Nothing -> do
                attempts <-
                    query @BillingCheckoutAttempt
                        |> filterWhere (#venueId, unpackId venue.id)
                        |> orderByDesc #createdAt
                        |> fetch
                case find (isJust . (.stripeCheckoutSessionId)) attempts of
                    Just attempt -> Right <$> enqueueBillingCheckoutReconciliation requestedByUserId attempt
                    Nothing -> pure (Left (reconciliationFailure "known_billing_object_missing" "This venue has no known Stripe Checkout Session or Subscription to reconcile."))

enqueueBillingReconciliationTarget
    :: (?modelContext :: ModelContext)
    => Maybe UUID
    -> UUID
    -> Text
    -> UUID
    -> BillingReconciliationTarget
    -> IO EnqueueAppJobResult
enqueueBillingReconciliationTarget requestedByUserId venueId relatedTable relatedId target =
    enqueueAppJob
        AppJobRequest
            { jobKind = billingReconciliationJobKind
            , payload = reconciliationTargetPayload target
            , payloadSchemaVersion = 1
            , requestedByUserId
            , venueId = Just venueId
            , relatedTable = Just relatedTable
            , relatedId = Just relatedId
            , dedupeKey = Just (billingReconciliationDedupeKey target)
            , runAt = Nothing
            }

reconciliationTargetPayload :: BillingReconciliationTarget -> Aeson.Value
reconciliationTargetPayload = \case
    ReconcileCheckoutAttempt attemptId ->
        Aeson.object
            [ "target" Aeson..= ("checkout_attempt" :: Text)
            , "localRecordId" Aeson..= inputValue attemptId
            ]
    ReconcileSubscription subscriptionId ->
        Aeson.object
            [ "target" Aeson..= ("subscription" :: Text)
            , "localRecordId" Aeson..= inputValue subscriptionId
            ]

billingReconciliationDedupeKey :: BillingReconciliationTarget -> Text
billingReconciliationDedupeKey = \case
    ReconcileCheckoutAttempt attemptId ->
        "billing-reconciliation:checkout:" <> inputValue attemptId
    ReconcileSubscription subscriptionId ->
        "billing-reconciliation:subscription:" <> inputValue subscriptionId

performBillingReconciliationJob
    :: (?modelContext :: ModelContext)
    => AppJob
    -> IO ()
performBillingReconciliationJob appJob = do
    attempted <-
        trySynchronousAppJobAction
            ( runBillingReconciliationJob appJob >>= \case
                Left failure -> pure (Left failure)
                Right outcome -> do
                    completeBillingReconciliationJob appJob outcome
                    pure (Right ())
            )
            :: IO (Either Exception.SomeException (Either BillingReconciliationFailure ()))
    case attempted of
        Left _ -> throwAppJobError JobUnexpectedSynchronousFailure
        Right (Left failure) -> throwAppJobError (billingReconciliationJobError failure)
        Right (Right ()) -> pure ()

billingReconciliationJobError :: BillingReconciliationFailure -> AppJobError
billingReconciliationJobError failure
    | code == "job_schema_invalid" = JobUnsupportedPayloadSchemaVersion
    | code == "job_payload_invalid" = JobMalformedPersistedPayload
    | code == "job_target_invalid" || code == "job_payload_mismatch" || "job_" `Text.isPrefixOf` code = JobInvalidProvenance
    | code == "stripe_config_unavailable" = JobConfigurationUnavailable
    | "retrieve_failed" `Text.isSuffixOf` code = JobTransportUnavailable
    | "mismatch" `Text.isInfixOf` code || "changed" `Text.isInfixOf` code || "advanced" `Text.isInfixOf` code || "already_associated" `Text.isInfixOf` code = JobRemoteConflict
    | "invalid" `Text.isInfixOf` code = JobValidationRejected
    | otherwise = JobValidationRejected
  where
    code = failure.reconciliationFailureCode

runBillingReconciliationJob
    :: (?modelContext :: ModelContext)
    => AppJob
    -> IO (Either BillingReconciliationFailure BillingReconciliationOutcome)
runBillingReconciliationJob appJob
    | appJob.payloadSchemaVersion /= 1 =
        pure (Left (reconciliationFailure "job_schema_invalid" "The billing reconciliation job schema is unsupported."))
    | otherwise =
        case Aeson.fromJSON appJob.payload :: Aeson.Result PersistedBillingReconciliationTarget of
            Aeson.Error _ -> pure (Left (reconciliationFailure "job_payload_invalid" "The billing reconciliation job payload is invalid."))
            Aeson.Success payload
                | not (billingPayloadMatchesJob payload appJob) -> pure (Left (reconciliationFailure "job_payload_mismatch" "The billing reconciliation job payload does not match its target."))
                | otherwise -> runTarget
  where
    runTarget =
        case (appJob.relatedTable, appJob.relatedId, appJob.venueId) of
            (Just "billing_checkout_attempts", Just relatedUuid, Just venueUuid) ->
                fetchOneOrNothing (Id relatedUuid :: Id BillingCheckoutAttempt) >>= \case
                    Nothing -> pure (Left (reconciliationFailure "checkout_attempt_missing" "The known Checkout attempt no longer exists."))
                    Just attempt
                        | attempt.venueId /= venueUuid -> pure (Left (reconciliationFailure "job_venue_mismatch" "The reconciliation job does not match the Checkout attempt venue."))
                        | otherwise -> withCurrentStripeConfig \client config -> reconcileKnownCheckoutAttempt client config attempt
            (Just "venue_subscriptions", Just relatedUuid, Just venueUuid) ->
                fetchOneOrNothing (Id relatedUuid :: Id VenueSubscription) >>= \case
                    Nothing -> pure (Left (reconciliationFailure "local_subscription_missing" "The known local Subscription no longer exists."))
                    Just subscription
                        | subscription.venueId /= venueUuid -> pure (Left (reconciliationFailure "job_venue_mismatch" "The reconciliation job does not match the Subscription venue."))
                        | otherwise -> withCurrentStripeConfig \client config -> reconcileKnownSubscription client config subscription
            _ -> pure (Left (reconciliationFailure "job_target_invalid" "The billing reconciliation job target is invalid."))

billingPayloadMatchesJob :: PersistedBillingReconciliationTarget -> AppJob -> Bool
billingPayloadMatchesJob payload appJob =
    case (payload.payloadTarget, appJob.relatedTable, appJob.relatedId) of
        ("checkout_attempt", Just "billing_checkout_attempts", Just relatedId) -> payload.payloadLocalRecordId == relatedId
        ("subscription", Just "venue_subscriptions", Just relatedId) -> payload.payloadLocalRecordId == relatedId
        _ -> False

withCurrentStripeConfig
    :: (StripeClient -> StripeConfig -> IO (Either BillingReconciliationFailure value))
    -> IO (Either BillingReconciliationFailure value)
withCurrentStripeConfig action =
    readStripeConfig >>= \case
        Left _ -> pure (Left (reconciliationFailure "stripe_config_unavailable" "Stripe configuration is unavailable for billing reconciliation."))
        Right stripeConfig -> do
            stripeClient <- currentStripeClient
            action stripeClient stripeConfig

completeBillingReconciliationJob
    :: (?modelContext :: ModelContext)
    => AppJob
    -> BillingReconciliationOutcome
    -> IO ()
completeBillingReconciliationJob appJob outcome =
    void $ withDurableLiveMutationWithoutContext "billing.reconciliation.complete" do
        void $
            appJob
                |> set #result (billingReconciliationResultPayload outcome)
                |> set #status JobStatusSucceeded
                |> set #lastError Nothing
                |> updateRecord
        pure (liveMutationResult outcome [billingResource (billingReconciliationOutcomeVenueId outcome)])

billingReconciliationPublication :: Text -> Either BillingReconciliationFailure BillingReconciliationOutcome -> Maybe (Text, Set.Set SurfaceResourceValue)
billingReconciliationPublication label = \case
    Left _ -> Nothing
    Right outcome -> Just (label, Set.singleton (billingResource (billingReconciliationOutcomeVenueId outcome)))

billingReconciliationResultPayload :: BillingReconciliationOutcome -> Aeson.Value
billingReconciliationResultPayload = \case
    BillingSubscriptionReconciled subscription ->
        Aeson.object
            [ "outcome" Aeson..= ("subscription_reconciled" :: Text)
            , "status" Aeson..= subscription.status
            , "lastSyncedAt" Aeson..= subscription.lastSyncedAt
            ]
    BillingCheckoutStillPending _ ->
        Aeson.object ["outcome" Aeson..= ("checkout_pending" :: Text)]
    BillingCheckoutExpired _ ->
        Aeson.object ["outcome" Aeson..= ("checkout_expired" :: Text)]

billingReconciliationOutcomeVenueId :: BillingReconciliationOutcome -> UUID
billingReconciliationOutcomeVenueId = \case
    BillingSubscriptionReconciled subscription -> subscription.venueId
    BillingCheckoutStillPending attempt -> attempt.venueId
    BillingCheckoutExpired attempt -> attempt.venueId

supportedSubscriptionStatuses :: [Text]
supportedSubscriptionStatuses =
    [ "incomplete"
    , "incomplete_expired"
    , "trialing"
    , "active"
    , "past_due"
    , "canceled"
    , "unpaid"
    , "paused"
    ]

checkoutExpiresAt :: StripeCheckoutSession -> UTCTime
checkoutExpiresAt checkoutSession =
    stripePeriodTime checkoutSession.stripeCheckoutExpiresAt

stripePeriodTime :: Integer -> UTCTime
stripePeriodTime = posixSecondsToUTCTime . fromInteger

reconciliationFailure :: Text -> Text -> BillingReconciliationFailure
reconciliationFailure code summary =
    BillingReconciliationFailure
        { reconciliationFailureCode = Text.take 120 code
        , reconciliationFailureSummary = Text.take 1000 summary
        }

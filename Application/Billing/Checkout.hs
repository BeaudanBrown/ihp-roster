{-# LANGUAGE RankNTypes #-}

module Application.Billing.Checkout
    ( BillingCheckoutPrincipal (..)
    , CheckoutStartOutcome (..)
    , CheckoutStartResult (..)
    , checkoutAllowedForSubscription
    , startOrResumeCheckoutForPrincipalWithTransaction
    )
where

import Application.Billing.Persistence (lockVenueForCheckout)
import Application.Billing.Stripe
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Generated.Types
import IHP.ControllerPrelude

data BillingCheckoutPrincipal = BillingCheckoutPrincipal
    { billingCheckoutActor :: !User
    , billingCheckoutPayer :: !User
    }

data CheckoutStartOutcome
    = CheckoutSessionReady !BillingCheckoutAttempt !StripeCheckoutSession
    | CheckoutAwaitingWebhook !BillingCheckoutAttempt
    | CheckoutStartRejected !Text
    deriving (Eq, Show)

data CheckoutStartResult = CheckoutStartResult
    { checkoutStartOutcome      :: !CheckoutStartOutcome
    , checkoutCreatedCustomer   :: !(Maybe VenueBillingCustomer)
    , checkoutAttemptWasCreated :: !Bool
    }
    deriving (Eq, Show)

-- | Immutable dependencies for one serialized Checkout operation. The public
-- boundary constructs this explicitly; internal lifecycle phases share it.
data CheckoutOperationContext = CheckoutOperationContext
    { operationStripeClient    :: !StripeClient
    , operationStripeConfig    :: !StripeConfig
    , operationVenue           :: !Venue
    , operationPrincipal       :: !BillingCheckoutPrincipal
    , operationCustomerCreated :: !(VenueBillingCustomer -> IO ())
    }

data PreparedCheckout = PreparedCheckout
    { preparedAttempt         :: !BillingCheckoutAttempt
    , preparedCreatedCustomer :: !(Maybe VenueBillingCustomer)
    , preparedAttemptCreated  :: !Bool
    }

data CheckoutPreparation
    = CheckoutPrepared !PreparedCheckout
    | CheckoutPreparationRejected !Text

data LockedCheckoutResult
    = CheckoutFinished !CheckoutStartResult !Bool
    | CheckoutRestart !PreparedCheckout

checkoutAllowedForSubscription :: Maybe VenueSubscription -> Bool
checkoutAllowedForSubscription Nothing = True
checkoutAllowedForSubscription (Just subscription) =
    subscription.status `elem` ["canceled", "incomplete_expired"]

startOrResumeCheckoutForPrincipalWithTransaction
    :: (?modelContext :: ModelContext)
    => (forall result. Text -> (result -> Bool) -> ((?modelContext :: ModelContext) => IO result) -> IO result)
    -> (VenueBillingCustomer -> IO ())
    -> StripeClient
    -> StripeConfig
    -> Venue
    -> BillingCheckoutPrincipal
    -> (Id BillingCheckoutAttempt -> Text)
    -> (Id BillingCheckoutAttempt -> Text)
    -> IO CheckoutStartResult
startOrResumeCheckoutForPrincipalWithTransaction runTransaction onCustomerCreated stripeClient stripeConfig venue principal successUrlFor cancelUrlFor =
    startCheckout runTransaction CheckoutOperationContext
        { operationStripeClient = stripeClient
        , operationStripeConfig = stripeConfig
        , operationVenue = venue
        , operationPrincipal = principal
        , operationCustomerCreated = onCustomerCreated
        }
        successUrlFor
        cancelUrlFor

startCheckout
    :: (?modelContext :: ModelContext)
    => (forall result. Text -> (result -> Bool) -> ((?modelContext :: ModelContext) => IO result) -> IO result)
    -> CheckoutOperationContext
    -> (Id BillingCheckoutAttempt -> Text)
    -> (Id BillingCheckoutAttempt -> Text)
    -> IO CheckoutStartResult
startCheckout runTransaction operation successUrlFor cancelUrlFor = do
    preparation <- runTransaction "billing.checkout.prepare" checkoutPreparationChanged do
        lockVenueForCheckout (unpackId operation.operationVenue.id)
        checkoutAllowedWhileVenueLocked operation.operationVenue.id >>= \case
            False -> pure (CheckoutPreparationRejected existingSubscriptionMessage)
            True -> do
                maybeOpenAttempt <- fetchOpenCheckoutAttempt operation.operationVenue.id
                case maybeOpenAttempt of
                    Just attempt -> pure (CheckoutPrepared (existingPreparedCheckout attempt))
                    Nothing ->
                        prepareNewCheckoutAttempt operation >>= \case
                            Left message -> pure (CheckoutPreparationRejected message)
                            Right prepared -> pure (CheckoutPrepared prepared)
    case preparation of
        CheckoutPreparationRejected message -> pure (checkoutRejected message)
        CheckoutPrepared prepared -> executePreparedCheckout runTransaction operation successUrlFor cancelUrlFor prepared
  where
    checkoutPreparationChanged = \case
        CheckoutPrepared prepared -> prepared.preparedAttemptCreated
        CheckoutPreparationRejected _ -> False

fetchVenueSubscription :: (?modelContext :: ModelContext) => Id Venue -> IO (Maybe VenueSubscription)
fetchVenueSubscription venueId =
    query @VenueSubscription
        |> filterWhere (#venueId, unpackId venueId)
        |> fetchOneOrNothing

-- | The caller owns the surrounding transaction and must already hold the
-- venue row lock. Keeping that ownership at each call site prevents provider
-- calls from accidentally moving outside the Checkout serialization boundary.
checkoutAllowedWhileVenueLocked :: (?modelContext :: ModelContext) => Id Venue -> IO Bool
checkoutAllowedWhileVenueLocked venueId =
    checkoutAllowedForSubscription <$> fetchVenueSubscription venueId

fetchOpenCheckoutAttempt :: (?modelContext :: ModelContext) => Id Venue -> IO (Maybe BillingCheckoutAttempt)
fetchOpenCheckoutAttempt venueId =
    query @BillingCheckoutAttempt
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#status, "open")
        |> fetchOneOrNothing

executePreparedCheckout
    :: (?modelContext :: ModelContext)
    => (forall result. Text -> (result -> Bool) -> ((?modelContext :: ModelContext) => IO result) -> IO result)
    -> CheckoutOperationContext
    -> (Id BillingCheckoutAttempt -> Text)
    -> (Id BillingCheckoutAttempt -> Text)
    -> PreparedCheckout
    -> IO CheckoutStartResult
executePreparedCheckout runTransaction operation successUrlFor cancelUrlFor prepared = do
    lockedResult <- runTransaction "billing.checkout.execute" checkoutExecutionChanged do
        lockVenueForCheckout (unpackId operation.operationVenue.id)
        checkoutAllowedWhileVenueLocked operation.operationVenue.id >>= \case
            False -> pure (CheckoutFinished (checkoutRejected existingSubscriptionMessage) False)
            True ->
                fetchOpenCheckoutAttempt operation.operationVenue.id >>= \case
                    Nothing -> pure (CheckoutFinished (checkoutRejected "The open Checkout attempt is no longer available.") False)
                    Just currentAttempt -> do
                        let currentPrepared =
                                if currentAttempt.id == prepared.preparedAttempt.id
                                    then prepared { preparedAttempt = currentAttempt }
                                    else existingPreparedCheckout currentAttempt
                        let attempt = currentPrepared.preparedAttempt
                        if attempt.livemode /= stripeModeIsLive operation.operationStripeConfig.stripeMode
                            then pure (CheckoutFinished (checkoutRejected "The open Checkout attempt belongs to a different Stripe mode.") False)
                            else
                                case attempt.stripeCheckoutSessionId of
                                    Nothing ->
                                        (\result -> CheckoutFinished result True) <$> createCheckoutSessionForAttempt operation successUrlFor cancelUrlFor currentPrepared
                                    Just sessionId ->
                                        operation.operationStripeClient.retrieveCheckoutSession operation.operationStripeConfig sessionId attempt.stripeCustomerId >>= \case
                                            Left err -> do
                                                _ <- recordAttemptError "stripe_checkout_retrieve_failed" (stripeClientErrorText err) attempt
                                                pure (CheckoutFinished (checkoutRejected ("Stripe Checkout could not be resumed: " <> stripeClientErrorText err)) True)
                                            Right checkoutSession ->
                                                applyRetrievedCheckoutSession operation currentPrepared checkoutSession
    case lockedResult of
        CheckoutFinished result _ -> pure result
        CheckoutRestart restarted -> executePreparedCheckout runTransaction operation successUrlFor cancelUrlFor restarted
  where
    checkoutExecutionChanged = \case
        CheckoutFinished _ changed -> changed
        CheckoutRestart _ -> True

applyRetrievedCheckoutSession
    :: (?modelContext :: ModelContext)
    => CheckoutOperationContext
    -> PreparedCheckout
    -> StripeCheckoutSession
    -> IO LockedCheckoutResult
applyRetrievedCheckoutSession operation prepared checkoutSession = do
    now <- getCurrentTime
    let attempt = prepared.preparedAttempt
    let providerExpiresAt = checkoutExpiresAt checkoutSession
    case checkoutSession.stripeCheckoutStatus of
        "expired" -> expireAndPrepareRestart attempt providerExpiresAt
        "open"
            | providerExpiresAt <= now -> expireAndPrepareRestart attempt providerExpiresAt
            | otherwise -> do
                resumedAttempt <-
                    attempt
                        |> set #expiresAt (Just providerExpiresAt)
                        |> set #errorCode Nothing
                        |> set #errorSummary Nothing
                        |> updateRecord
                pure (CheckoutFinished (checkoutReady prepared resumedAttempt checkoutSession) True)
        "complete" -> do
            pendingAttempt <-
                attempt
                    |> set #stripeSubscriptionId checkoutSession.stripeCheckoutSubscriptionId
                    |> set #expiresAt (Just providerExpiresAt)
                    |> set #errorCode Nothing
                    |> set #errorSummary Nothing
                    |> updateRecord
            pure $
                CheckoutFinished
                    CheckoutStartResult
                        { checkoutStartOutcome = CheckoutAwaitingWebhook pendingAttempt
                        , checkoutCreatedCustomer = prepared.preparedCreatedCustomer
                        , checkoutAttemptWasCreated = prepared.preparedAttemptCreated
                        }
                    True
        _ -> pure (CheckoutFinished (checkoutRejected "Stripe Checkout returned an unexpected status while resuming the attempt.") False)
  where
    expireAndPrepareRestart attempt providerExpiresAt = do
        _ <-
            attempt
                |> set #status "expired"
                |> set #expiresAt (Just providerExpiresAt)
                |> set #errorCode Nothing
                |> set #errorSummary Nothing
                |> updateRecord
        prepareNewCheckoutAttempt operation >>= \case
            Left message -> pure (CheckoutFinished (checkoutRejected message) True)
            Right restarted -> pure (CheckoutRestart restarted)

prepareNewCheckoutAttempt
    :: (?modelContext :: ModelContext)
    => CheckoutOperationContext
    -> IO (Either Text PreparedCheckout)
prepareNewCheckoutAttempt operation =
    resolveBillingPrice operation.operationStripeClient operation.operationStripeConfig >>= \case
        Left message -> pure (Left message)
        Right price ->
            ensureVenueStripeCustomer operation >>= \case
                Left message -> pure (Left message)
                Right (billingCustomer, customerWasCreated) -> do
                    attempt <-
                        newRecord @BillingCheckoutAttempt
                            |> set #venueId (unpackId operation.operationVenue.id)
                            |> set #initiatedByUserId (unpackId operation.operationPrincipal.billingCheckoutActor.id)
                            |> set #livemode (stripeModeIsLive operation.operationStripeConfig.stripeMode)
                            |> set #stripeCustomerId billingCustomer.stripeCustomerId
                            |> set #stripePriceId price.stripePriceId
                            |> createRecord
                    pure $ Right PreparedCheckout
                        { preparedAttempt = attempt
                        , preparedCreatedCustomer = if customerWasCreated then Just billingCustomer else Nothing
                        , preparedAttemptCreated = True
                        }

createCheckoutSessionForAttempt
    :: (?modelContext :: ModelContext)
    => CheckoutOperationContext
    -> (Id BillingCheckoutAttempt -> Text)
    -> (Id BillingCheckoutAttempt -> Text)
    -> PreparedCheckout
    -> IO CheckoutStartResult
createCheckoutSessionForAttempt operation successUrlFor cancelUrlFor prepared = do
    let attempt = prepared.preparedAttempt
    checkoutResult <-
        operation.operationStripeClient.createCheckoutSession
            operation.operationStripeConfig
            (inputValue attempt.id)
            (inputValue operation.operationVenue.id)
            attempt.stripeCustomerId
            attempt.stripePriceId
            (successUrlFor attempt.id)
            (cancelUrlFor attempt.id)
    case checkoutResult of
        Left err -> do
            _ <- recordAttemptError "stripe_checkout_create_failed" (stripeClientErrorText err) attempt
            pure CheckoutStartResult
                { checkoutStartOutcome = CheckoutStartRejected ("Stripe Checkout failed: " <> stripeClientErrorText err)
                , checkoutCreatedCustomer = prepared.preparedCreatedCustomer
                , checkoutAttemptWasCreated = prepared.preparedAttemptCreated
                }
        Right checkoutSession ->
            case validateCreatedCheckoutSession attempt.stripeCustomerId checkoutSession of
                Left message -> do
                    _ <- recordAttemptError "stripe_checkout_response_invalid" message attempt
                    pure CheckoutStartResult
                        { checkoutStartOutcome = CheckoutStartRejected message
                        , checkoutCreatedCustomer = prepared.preparedCreatedCustomer
                        , checkoutAttemptWasCreated = prepared.preparedAttemptCreated
                        }
                Right validatedCheckoutSession -> do
                    updatedAttempt <-
                        attempt
                            |> set #stripeCheckoutSessionId (Just validatedCheckoutSession.stripeCheckoutSessionId)
                            |> set #expiresAt (Just (checkoutExpiresAt validatedCheckoutSession))
                            |> set #errorCode Nothing
                            |> set #errorSummary Nothing
                            |> updateRecord
                    pure (checkoutReady prepared updatedAttempt validatedCheckoutSession)

ensureVenueStripeCustomer
    :: (?modelContext :: ModelContext)
    => CheckoutOperationContext
    -> IO (Either Text (VenueBillingCustomer, Bool))
ensureVenueStripeCustomer operation =
    query @VenueBillingCustomer
        |> filterWhere (#venueId, unpackId operation.operationVenue.id)
        |> fetchOneOrNothing
        >>= \case
            Just customer
                | customer.livemode == stripeModeIsLive operation.operationStripeConfig.stripeMode -> pure (Right (customer, False))
                | otherwise -> pure (Left "The venue Customer belongs to a different Stripe mode.")
            Nothing
                | isNothing operation.operationPrincipal.billingCheckoutPayer.emailVerifiedAt -> pure (Left "Verify your account email before starting Checkout.")
                | otherwise ->
                    operation.operationStripeClient.createCustomer operation.operationStripeConfig (inputValue operation.operationVenue.id) operation.operationVenue.name operation.operationPrincipal.billingCheckoutPayer.email >>= \case
                        Left err -> pure (Left ("Stripe Customer create failed: " <> stripeClientErrorText err))
                        Right stripeCustomer
                            | stripeCustomer.stripeCustomerLivemode /= stripeModeIsLive operation.operationStripeConfig.stripeMode ->
                                pure (Left "Stripe Customer creation returned data from a different mode.")
                            | otherwise -> do
                                customer <-
                                    newRecord @VenueBillingCustomer
                                        |> set #venueId (unpackId operation.operationVenue.id)
                                        |> set #stripeCustomerId stripeCustomer.stripeCustomerId
                                        |> set #livemode stripeCustomer.stripeCustomerLivemode
                                        |> set #createdByUserId (Just (unpackId operation.operationPrincipal.billingCheckoutActor.id))
                                        |> createRecord
                                operation.operationCustomerCreated customer
                                pure (Right (customer, True))

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

recordAttemptError
    :: (?modelContext :: ModelContext)
    => Text
    -> Text
    -> BillingCheckoutAttempt
    -> IO BillingCheckoutAttempt
recordAttemptError errorCode errorSummary attempt =
    attempt
        |> set #errorCode (Just errorCode)
        |> set #errorSummary (Just errorSummary)
        |> updateRecord

checkoutReady :: PreparedCheckout -> BillingCheckoutAttempt -> StripeCheckoutSession -> CheckoutStartResult
checkoutReady prepared attempt checkoutSession =
    CheckoutStartResult
        { checkoutStartOutcome = CheckoutSessionReady attempt checkoutSession
        , checkoutCreatedCustomer = prepared.preparedCreatedCustomer
        , checkoutAttemptWasCreated = prepared.preparedAttemptCreated
        }

existingPreparedCheckout :: BillingCheckoutAttempt -> PreparedCheckout
existingPreparedCheckout attempt =
    PreparedCheckout
        { preparedAttempt = attempt
        , preparedCreatedCustomer = Nothing
        , preparedAttemptCreated = False
        }

checkoutExpiresAt :: StripeCheckoutSession -> UTCTime
checkoutExpiresAt checkoutSession =
    posixSecondsToUTCTime (fromInteger checkoutSession.stripeCheckoutExpiresAt)

checkoutRejected :: Text -> CheckoutStartResult
checkoutRejected message =
    CheckoutStartResult
        { checkoutStartOutcome = CheckoutStartRejected message
        , checkoutCreatedCustomer = Nothing
        , checkoutAttemptWasCreated = False
        }

existingSubscriptionMessage :: Text
existingSubscriptionMessage =
    "An existing subscription must be managed before starting another Checkout."

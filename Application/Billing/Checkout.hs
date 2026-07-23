module Application.Billing.Checkout
    ( CheckoutStartOutcome (..)
    , CheckoutStartResult (..)
    , checkoutAllowedForSubscription
    , startOrResumeCheckout
    )
where

import Application.Billing.Stripe
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Tuple.Only (Only (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlQuery, withTransaction)

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

data PreparedCheckout = PreparedCheckout
    { preparedAttempt         :: !BillingCheckoutAttempt
    , preparedCreatedCustomer :: !(Maybe VenueBillingCustomer)
    , preparedAttemptCreated  :: !Bool
    }

data CheckoutPreparation
    = CheckoutPrepared !PreparedCheckout
    | CheckoutPreparationRejected !Text

data LockedCheckoutResult
    = CheckoutFinished !CheckoutStartResult
    | CheckoutRestart !PreparedCheckout

checkoutAllowedForSubscription :: Maybe VenueSubscription -> Bool
checkoutAllowedForSubscription Nothing = True
checkoutAllowedForSubscription (Just subscription) =
    subscription.status `elem` ["canceled", "incomplete_expired"]

startOrResumeCheckout
    :: (?modelContext :: ModelContext)
    => StripeClient
    -> StripeConfig
    -> Venue
    -> User
    -> (Id BillingCheckoutAttempt -> Text)
    -> (Id BillingCheckoutAttempt -> Text)
    -> IO CheckoutStartResult
startOrResumeCheckout stripeClient stripeConfig venue owner successUrlFor cancelUrlFor = do
    preparation <- withTransaction do
        lockVenueForCheckout venue.id
        maybeSubscription <- fetchVenueSubscription venue.id
        if not (checkoutAllowedForSubscription maybeSubscription)
            then pure (CheckoutPreparationRejected existingSubscriptionMessage)
            else do
                maybeOpenAttempt <- fetchOpenCheckoutAttempt venue.id
                case maybeOpenAttempt of
                    Just attempt -> pure (CheckoutPrepared (existingPreparedCheckout attempt))
                    Nothing ->
                        prepareNewCheckoutAttempt stripeClient stripeConfig venue owner >>= \case
                            Left message -> pure (CheckoutPreparationRejected message)
                            Right prepared -> pure (CheckoutPrepared prepared)
    case preparation of
        CheckoutPreparationRejected message -> pure (checkoutRejected message)
        CheckoutPrepared prepared ->
            executePreparedCheckout stripeClient stripeConfig venue owner successUrlFor cancelUrlFor prepared

lockVenueForCheckout :: (?modelContext :: ModelContext) => Id Venue -> IO ()
lockVenueForCheckout venueId = do
    lockedVenues :: [Venue] <-
        sqlQuery
            "SELECT venues.* FROM venues WHERE id = ? FOR UPDATE"
            (Only (unpackId venueId))
    unless (length lockedVenues == 1) do
        error "Unable to lock the venue for Checkout"

fetchVenueSubscription :: (?modelContext :: ModelContext) => Id Venue -> IO (Maybe VenueSubscription)
fetchVenueSubscription venueId =
    query @VenueSubscription
        |> filterWhere (#venueId, unpackId venueId)
        |> fetchOneOrNothing

fetchOpenCheckoutAttempt :: (?modelContext :: ModelContext) => Id Venue -> IO (Maybe BillingCheckoutAttempt)
fetchOpenCheckoutAttempt venueId =
    query @BillingCheckoutAttempt
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#status, "open")
        |> fetchOneOrNothing

executePreparedCheckout
    :: (?modelContext :: ModelContext)
    => StripeClient
    -> StripeConfig
    -> Venue
    -> User
    -> (Id BillingCheckoutAttempt -> Text)
    -> (Id BillingCheckoutAttempt -> Text)
    -> PreparedCheckout
    -> IO CheckoutStartResult
executePreparedCheckout stripeClient stripeConfig venue owner successUrlFor cancelUrlFor prepared = do
    lockedResult <- withTransaction do
        lockVenueForCheckout venue.id
        maybeSubscription <- fetchVenueSubscription venue.id
        if not (checkoutAllowedForSubscription maybeSubscription)
            then pure (CheckoutFinished (checkoutRejected existingSubscriptionMessage))
            else
                fetchOpenCheckoutAttempt venue.id >>= \case
                    Nothing -> pure (CheckoutFinished (checkoutRejected "The open Checkout attempt is no longer available."))
                    Just currentAttempt -> do
                        let currentPrepared =
                                if currentAttempt.id == prepared.preparedAttempt.id
                                    then prepared { preparedAttempt = currentAttempt }
                                    else existingPreparedCheckout currentAttempt
                        processLockedCheckoutAttempt
                            stripeClient
                            stripeConfig
                            venue
                            owner
                            successUrlFor
                            cancelUrlFor
                            currentPrepared
    case lockedResult of
        CheckoutFinished result -> pure result
        CheckoutRestart restarted ->
            executePreparedCheckout stripeClient stripeConfig venue owner successUrlFor cancelUrlFor restarted

processLockedCheckoutAttempt
    :: (?modelContext :: ModelContext)
    => StripeClient
    -> StripeConfig
    -> Venue
    -> User
    -> (Id BillingCheckoutAttempt -> Text)
    -> (Id BillingCheckoutAttempt -> Text)
    -> PreparedCheckout
    -> IO LockedCheckoutResult
processLockedCheckoutAttempt stripeClient stripeConfig venue owner successUrlFor cancelUrlFor prepared
    | attempt.livemode /= stripeModeIsLive stripeConfig.stripeMode =
        pure (CheckoutFinished (checkoutRejected "The open Checkout attempt belongs to a different Stripe mode."))
    | otherwise =
        case attempt.stripeCheckoutSessionId of
            Nothing ->
                CheckoutFinished
                    <$> createCheckoutSessionForAttempt
                        stripeClient
                        stripeConfig
                        venue
                        successUrlFor
                        cancelUrlFor
                        prepared
            Just sessionId ->
                stripeClient.retrieveCheckoutSession stripeConfig sessionId attempt.stripeCustomerId >>= \case
                    Left err -> do
                        _ <- recordAttemptError "stripe_checkout_retrieve_failed" (stripeClientErrorText err) attempt
                        pure (CheckoutFinished (checkoutRejected ("Stripe Checkout could not be resumed: " <> stripeClientErrorText err)))
                    Right checkoutSession ->
                        applyRetrievedCheckoutSession stripeClient stripeConfig venue owner prepared checkoutSession
  where
    attempt = prepared.preparedAttempt

applyRetrievedCheckoutSession
    :: (?modelContext :: ModelContext)
    => StripeClient
    -> StripeConfig
    -> Venue
    -> User
    -> PreparedCheckout
    -> StripeCheckoutSession
    -> IO LockedCheckoutResult
applyRetrievedCheckoutSession stripeClient stripeConfig venue owner prepared checkoutSession = do
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
                pure (CheckoutFinished (checkoutReady prepared resumedAttempt checkoutSession))
        "complete" -> do
            pendingAttempt <-
                attempt
                    |> set #stripeSubscriptionId checkoutSession.stripeCheckoutSubscriptionId
                    |> set #expiresAt (Just providerExpiresAt)
                    |> set #errorCode Nothing
                    |> set #errorSummary Nothing
                    |> updateRecord
            pure $ CheckoutFinished CheckoutStartResult
                { checkoutStartOutcome = CheckoutAwaitingWebhook pendingAttempt
                , checkoutCreatedCustomer = prepared.preparedCreatedCustomer
                , checkoutAttemptWasCreated = prepared.preparedAttemptCreated
                }
        _ -> pure (CheckoutFinished (checkoutRejected "Stripe Checkout returned an unexpected status while resuming the attempt."))
  where
    expireAndPrepareRestart attempt providerExpiresAt = do
        _ <-
            attempt
                |> set #status "expired"
                |> set #expiresAt (Just providerExpiresAt)
                |> set #errorCode Nothing
                |> set #errorSummary Nothing
                |> updateRecord
        prepareNewCheckoutAttempt stripeClient stripeConfig venue owner >>= \case
            Left message -> pure (CheckoutFinished (checkoutRejected message))
            Right restarted -> pure (CheckoutRestart restarted)

prepareNewCheckoutAttempt
    :: (?modelContext :: ModelContext)
    => StripeClient
    -> StripeConfig
    -> Venue
    -> User
    -> IO (Either Text PreparedCheckout)
prepareNewCheckoutAttempt stripeClient stripeConfig venue owner =
    resolveBillingPrice stripeClient stripeConfig >>= \case
        Left message -> pure (Left message)
        Right price ->
            ensureVenueStripeCustomer stripeClient stripeConfig venue owner >>= \case
                Left message -> pure (Left message)
                Right (billingCustomer, customerWasCreated) -> do
                    attempt <-
                        newRecord @BillingCheckoutAttempt
                            |> set #venueId (unpackId venue.id)
                            |> set #initiatedByUserId (unpackId owner.id)
                            |> set #livemode (stripeModeIsLive stripeConfig.stripeMode)
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
    => StripeClient
    -> StripeConfig
    -> Venue
    -> (Id BillingCheckoutAttempt -> Text)
    -> (Id BillingCheckoutAttempt -> Text)
    -> PreparedCheckout
    -> IO CheckoutStartResult
createCheckoutSessionForAttempt stripeClient stripeConfig venue successUrlFor cancelUrlFor prepared = do
    let attempt = prepared.preparedAttempt
    checkoutResult <-
        stripeClient.createCheckoutSession
            stripeConfig
            (inputValue attempt.id)
            (inputValue venue.id)
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
    => StripeClient
    -> StripeConfig
    -> Venue
    -> User
    -> IO (Either Text (VenueBillingCustomer, Bool))
ensureVenueStripeCustomer stripeClient stripeConfig venue owner =
    query @VenueBillingCustomer
        |> filterWhere (#venueId, unpackId venue.id)
        |> fetchOneOrNothing
        >>= \case
            Just customer
                | customer.livemode == stripeModeIsLive stripeConfig.stripeMode -> pure (Right (customer, False))
                | otherwise -> pure (Left "The venue Customer belongs to a different Stripe mode.")
            Nothing
                | isNothing owner.emailVerifiedAt -> pure (Left "Verify your account email before starting Checkout.")
                | otherwise ->
                    stripeClient.createCustomer stripeConfig (inputValue venue.id) venue.name owner.email >>= \case
                        Left err -> pure (Left ("Stripe Customer create failed: " <> stripeClientErrorText err))
                        Right stripeCustomer
                            | stripeCustomer.stripeCustomerLivemode /= stripeModeIsLive stripeConfig.stripeMode ->
                                pure (Left "Stripe Customer creation returned data from a different mode.")
                            | otherwise -> do
                                customer <-
                                    newRecord @VenueBillingCustomer
                                        |> set #venueId (unpackId venue.id)
                                        |> set #stripeCustomerId stripeCustomer.stripeCustomerId
                                        |> set #livemode stripeCustomer.stripeCustomerLivemode
                                        |> set #createdByUserId (Just (unpackId owner.id))
                                        |> createRecord
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

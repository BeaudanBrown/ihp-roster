module Application.Billing.Webhook
    ( BillingWebhookResult (..)
    , StripeWebhookEvent (..)
    , handleStripeWebhookPayloadInCurrentTransaction
    , parseStripeWebhookEvent
    )
where

import Application.Billing.Notifications (BillingNotification (..),
                                          BillingNotificationKind (..),
                                          enqueueBillingNotifications)
import Application.Billing.Persistence (lockStripeEventForWebhook,
                                        lockVenueForBilling)
import Application.Billing.Stripe (StripeMode, StripeSubscription (..),
                                   pinnedStripeApiVersion, stripeModeIsLive)
import Application.Error.Parser (parserFailure)
import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Control.Monad (guard, void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString.Lazy as LByteString
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import qualified Data.UUID as UUID
import qualified Data.Vector as Vector
import Generated.Types
import IHP.ControllerPrelude

data BillingWebhookResult
    = BillingWebhookProcessed !BillingEvent
    | BillingWebhookDuplicate !BillingEvent
    | BillingWebhookIgnored !BillingEvent
    deriving (Eq, Show)

data StripeWebhookEvent = StripeWebhookEvent
    { stripeEventId        :: !Text
    , stripeEventType      :: !Text
    , stripeEventCreatedAt :: !UTCTime
    , stripeLivemode       :: !Bool
    , stripeApiVersion     :: !(Maybe Text)
    , stripeObjectSnapshot :: !StripeObjectSnapshot
    }
    deriving (Eq, Show)

data StripeObjectSnapshot = StripeObjectSnapshot
    { stripeObjectType               :: !Text
    , stripeObjectId                 :: !(Maybe Text)
    , stripeObjectLivemode           :: !Bool
    , stripeObjectPriceLivemode      :: !(Maybe Bool)
    , stripeObjectCustomerId         :: !(Maybe Text)
    , stripeObjectSubscriptionId     :: !(Maybe Text)
    , stripeObjectClientReferenceId  :: !(Maybe Text)
    , stripeObjectMetadataVenueId    :: !(Maybe Text)
    , stripeObjectStatus             :: !(Maybe Text)
    , stripeObjectPriceId            :: !(Maybe Text)
    , stripeObjectCurrentPeriodStart :: !(Maybe Integer)
    , stripeObjectCurrentPeriodEnd   :: !(Maybe Integer)
    , stripeObjectCancelAtPeriodEnd  :: !Bool
    }
    deriving (Eq, Show)

instance Aeson.FromJSON StripeWebhookEvent where
    parseJSON =
        Aeson.withObject "StripeWebhookEvent" \object -> do
            eventObjectType <- object Aeson..: "object"
            unless (eventObjectType == ("event" :: Text)) (parserFailure "Stripe webhook root object discriminator must be event")
            dataObject <- object Aeson..: "data"
            stripeObject <- dataObject Aeson..: "object"
            StripeWebhookEvent
                <$> object Aeson..: "id"
                <*> object Aeson..: "type"
                <*> (posixSecondsToUTCTime . fromInteger <$> object Aeson..: "created")
                <*> object Aeson..: "livemode"
                <*> object Aeson..:? "api_version"
                <*> parseStripeObjectSnapshot stripeObject

parseStripeObjectSnapshot :: Aeson.Value -> AesonTypes.Parser StripeObjectSnapshot
parseStripeObjectSnapshot stripeObject =
    Aeson.withObject "StripeObjectSnapshot" (parseObject stripeObject) stripeObject
  where
    parseObject originalValue object = do
        metadata <- object Aeson..:? "metadata" Aeson..!= Aeson.Object mempty
        objectType <- object Aeson..: "object"
        subscriptionContract <-
            case objectType of
                "subscription" -> Just <$> (Aeson.parseJSON originalValue :: AesonTypes.Parser StripeSubscription)
                _ -> pure Nothing
        objectId <- object Aeson..:? "id"
        objectLivemode <- object Aeson..: "livemode"
        customerId <- object Aeson..:? "customer"
        legacySubscriptionId <- object Aeson..:? "subscription"
        invoiceParent <- object Aeson..:? "parent"
        parentSubscriptionId <- maybe (pure Nothing) parseInvoiceParentSubscriptionId invoiceParent
        let subscriptionId = legacySubscriptionId <|> parentSubscriptionId
        clientReferenceId <- object Aeson..:? "client_reference_id"
        metadataVenueId <- parseMetadataVenueId metadata
        status <- object Aeson..:? "status"
        priceId <- parseObjectPriceId object
        currentPeriodStart <- object Aeson..:? "current_period_start"
        currentPeriodEnd <- object Aeson..:? "current_period_end"
        invoicePeriodStart <- object Aeson..:? "period_start"
        invoicePeriodEnd <- object Aeson..:? "period_end"
        cancelAtPeriodEnd <- object Aeson..:? "cancel_at_period_end" Aeson..!= False
        pure
            StripeObjectSnapshot
                { stripeObjectType = objectType
                , stripeObjectId = objectId
                , stripeObjectLivemode = maybe objectLivemode (.stripeSubscriptionLivemode) subscriptionContract
                , stripeObjectPriceLivemode = (.stripeSubscriptionPriceLivemode) <$> subscriptionContract
                , stripeObjectCustomerId = maybe customerId (Just . (.stripeSubscriptionCustomerId)) subscriptionContract
                , stripeObjectSubscriptionId = maybe subscriptionId (Just . (.stripeSubscriptionId)) subscriptionContract
                , stripeObjectClientReferenceId = clientReferenceId
                , stripeObjectMetadataVenueId = metadataVenueId
                , stripeObjectStatus = maybe status (Just . (.stripeSubscriptionStatus)) subscriptionContract
                , stripeObjectPriceId = maybe priceId (Just . (.stripeSubscriptionPriceId)) subscriptionContract
                , stripeObjectCurrentPeriodStart = maybe (currentPeriodStart <|> invoicePeriodStart) (Just . (.stripeSubscriptionCurrentPeriodStart)) subscriptionContract
                , stripeObjectCurrentPeriodEnd = maybe (currentPeriodEnd <|> invoicePeriodEnd) (Just . (.stripeSubscriptionCurrentPeriodEnd)) subscriptionContract
                , stripeObjectCancelAtPeriodEnd = maybe cancelAtPeriodEnd (.stripeSubscriptionCancelAtPeriodEnd) subscriptionContract
                }

parseInvoiceParentSubscriptionId :: Aeson.Value -> AesonTypes.Parser (Maybe Text)
parseInvoiceParentSubscriptionId =
    Aeson.withObject "StripeInvoiceParent" \parent ->
        parent Aeson..:? "subscription_details" >>= \case
            Nothing -> pure Nothing
            Just subscriptionDetails ->
                Aeson.withObject "StripeInvoiceSubscriptionParent" parseSubscriptionDetails subscriptionDetails
  where
    parseSubscriptionDetails details =
        details Aeson..:? "subscription" >>= \case
            Nothing -> pure Nothing
            Just subscription -> parseExpandableId subscription

    parseExpandableId = \case
        Aeson.String subscriptionId -> pure (Just subscriptionId)
        Aeson.Object subscription -> subscription Aeson..:? "id"
        Aeson.Null -> pure Nothing
        _ -> parserFailure "Stripe invoice parent subscription must be an id or expanded object"

parseMetadataVenueId :: Aeson.Value -> AesonTypes.Parser (Maybe Text)
parseMetadataVenueId =
    Aeson.withObject "StripeMetadata" (Aeson..:? "venue_id")

parseObjectPriceId :: Aeson.Object -> AesonTypes.Parser (Maybe Text)
parseObjectPriceId object =
    case AesonKeyMap.lookup (AesonKey.fromString "items") object of
        Nothing         -> pure Nothing
        Just itemsValue -> parseItemsPriceId itemsValue

parseItemsPriceId :: Aeson.Value -> AesonTypes.Parser (Maybe Text)
parseItemsPriceId =
    Aeson.withObject "StripeSubscriptionItems" \itemsObject ->
        case AesonKeyMap.lookup (AesonKey.fromString "data") itemsObject of
            Just (Aeson.Array values) ->
                case Vector.toList values of
                    firstItem : _ -> parseItemPriceId firstItem
                    []            -> pure Nothing
            _ -> pure Nothing

parseItemPriceId :: Aeson.Value -> AesonTypes.Parser (Maybe Text)
parseItemPriceId =
    Aeson.withObject "StripeSubscriptionItem" \itemObject ->
        case AesonKeyMap.lookup (AesonKey.fromString "price") itemObject of
            Just (Aeson.Object priceObject) -> priceObject Aeson..:? "id"
            _                               -> pure Nothing

parseStripeWebhookEvent :: LByteString.ByteString -> Either Text StripeWebhookEvent
parseStripeWebhookEvent rawBody =
    case Aeson.eitherDecode rawBody of
        Left err    -> Left ("Unable to decode Stripe webhook event: " <> cs err)
        Right event -> Right event

handleStripeWebhookPayloadInCurrentTransaction :: (?modelContext :: ModelContext) => StripeMode -> LByteString.ByteString -> IO (Either Text BillingWebhookResult)
handleStripeWebhookPayloadInCurrentTransaction expectedMode rawBody =
    case parseStripeWebhookEvent rawBody >>= validateStripeWebhookContract expectedMode of
        Left err    -> pure (Left err)
        Right event -> Right <$> processStripeWebhookEventInCurrentTransaction event

validateStripeWebhookContract :: StripeMode -> StripeWebhookEvent -> Either Text StripeWebhookEvent
validateStripeWebhookContract expectedMode event = do
    unless (event.stripeApiVersion == Just pinnedStripeApiVersion) do
        Left "Stripe webhook API version does not match the pinned billing contract"
    unless (event.stripeLivemode == stripeModeIsLive expectedMode) do
        Left "Stripe webhook mode does not match the configured billing mode"
    unless (event.stripeObjectSnapshot.stripeObjectLivemode == event.stripeLivemode) do
        Left "Stripe webhook object mode does not match the event mode"
    forM_ (stripeWebhookEventContract event.stripeEventType).expectedSnapshotObjectType \expectedObjectType ->
        unless (event.stripeObjectSnapshot.stripeObjectType == expectedObjectType) do
            Left "Stripe webhook snapshot object discriminator does not match the event type"
    forM_ event.stripeObjectSnapshot.stripeObjectPriceLivemode \priceLivemode ->
        unless (priceLivemode == event.stripeLivemode) do
            Left "Stripe webhook Subscription Item Price mode does not match the event mode"
    pure event

data StripeWebhookApplication
    = ApplyCheckoutCustomer
    | ApplySubscriptionSnapshot
    | ApplyInvoicePaymentFailure
    | IgnoreWebhookEvent

data StripeWebhookEventContract = StripeWebhookEventContract
    { expectedSnapshotObjectType :: !(Maybe Text)
    , webhookApplication         :: !StripeWebhookApplication
    }

stripeWebhookEventContract :: Text -> StripeWebhookEventContract
stripeWebhookEventContract eventType
    | eventType `elem` ["checkout.session.completed", "checkout.session.async_payment_succeeded", "checkout.session.async_payment_failed"] =
        StripeWebhookEventContract (Just "checkout.session") ApplyCheckoutCustomer
    | eventType `elem` ["customer.subscription.created", "customer.subscription.updated", "customer.subscription.deleted"] =
        StripeWebhookEventContract (Just "subscription") ApplySubscriptionSnapshot
    | eventType == "invoice.payment_failed" =
        StripeWebhookEventContract (Just "invoice") ApplyInvoicePaymentFailure
    | otherwise =
        StripeWebhookEventContract Nothing IgnoreWebhookEvent

-- Every durable webhook effect is part of this transaction. In particular, do
-- not turn a supported-event exception into a failed event row: Stripe must see
-- a non-success response and retry the whole event instead.
processStripeWebhookEventInCurrentTransaction :: (?modelContext :: ModelContext) => StripeWebhookEvent -> IO BillingWebhookResult
processStripeWebhookEventInCurrentTransaction event = do
        lockStripeEventForWebhook event.stripeEventId
        existing <- query @BillingEvent |> filterWhere (#stripeEventId, event.stripeEventId) |> fetchOneOrNothing
        case existing of
            Just billingEvent -> pure (BillingWebhookDuplicate billingEvent)
            Nothing -> do
                maybeVenue <- resolveAndLockStripeEventVenue event
                now <- getCurrentTime
                billingEvent <- createBillingEventRecord event maybeVenue
                applyStripeEvent now event maybeVenue >>= \case
                    ApplyIgnored -> do
                        ignoredEvent <- billingEvent |> set #status "ignored" |> updateRecord
                        pure (BillingWebhookIgnored ignoredEvent)
                    ApplyProcessed notifications -> do
                        processedEvent <-
                            billingEvent
                                |> set #status "processed"
                                |> set #processedAt (Just now)
                                |> set #notificationSnapshot (Aeson.toJSON notifications)
                                |> updateRecord
                        forM_ notifications \notification ->
                            forM_ maybeVenue \venue ->
                                void (enqueueBillingNotifications venue processedEvent notification)
                        pure (BillingWebhookProcessed processedEvent)

createBillingEventRecord :: (?modelContext :: ModelContext) => StripeWebhookEvent -> Maybe Venue -> IO BillingEvent
createBillingEventRecord event maybeVenue =
    newRecord @BillingEvent
        |> set #stripeEventId event.stripeEventId
        |> set #eventType event.stripeEventType
        |> set #stripeCreatedAt (Just event.stripeEventCreatedAt)
        |> set #livemode event.stripeLivemode
        |> set #apiVersion event.stripeApiVersion
        |> set #providerObjectType (Just event.stripeObjectSnapshot.stripeObjectType)
        |> set #providerObjectId event.stripeObjectSnapshot.stripeObjectId
        |> set #venueId (unpackId . (.id) <$> maybeVenue)
        |> set #stripeCustomerId event.stripeObjectSnapshot.stripeObjectCustomerId
        |> set #stripeSubscriptionId event.stripeObjectSnapshot.stripeObjectSubscriptionId
        |> set #notificationSnapshot (Aeson.Array mempty)
        |> createRecord

data ApplyResult
    = ApplyProcessed ![BillingNotification]
    | ApplyIgnored
    deriving (Eq, Show)

applyStripeEvent :: (?modelContext :: ModelContext) => UTCTime -> StripeWebhookEvent -> Maybe Venue -> IO ApplyResult
applyStripeEvent now event maybeVenue =
    case (stripeWebhookEventContract event.stripeEventType).webhookApplication of
        ApplyCheckoutCustomer      -> applyCheckoutEvent now maybeVenue event
        ApplySubscriptionSnapshot  -> upsertSubscription now maybeVenue event
        ApplyInvoicePaymentFailure -> applyInvoicePaymentFailure maybeVenue event
        IgnoreWebhookEvent         -> pure ApplyIgnored

applyCheckoutEvent :: (?modelContext :: ModelContext) => UTCTime -> Maybe Venue -> StripeWebhookEvent -> IO ApplyResult
applyCheckoutEvent now maybeVenue event = do
    ensureCheckoutCustomer maybeVenue event
    checkoutSnapshotWasApplied <- updateCheckoutAttempt now maybeVenue event
    notifications <-
        if checkoutSnapshotWasApplied && isCheckoutPaymentFailure event
            then checkoutPaymentFailureNotifications maybeVenue event
            else pure []
    pure (ApplyProcessed notifications)

ensureCheckoutCustomer :: (?modelContext :: ModelContext) => Maybe Venue -> StripeWebhookEvent -> IO ()
ensureCheckoutCustomer Nothing _ = pure ()
ensureCheckoutCustomer (Just venue) event =
    forM_ event.stripeObjectSnapshot.stripeObjectCustomerId \customerId -> do
        existing <-
            query @VenueBillingCustomer
                |> filterWhere (#venueId, unpackId venue.id)
                |> fetchOneOrNothing
        case existing of
            Just customer
                | customer.stripeCustomerId == customerId && customer.livemode == event.stripeLivemode -> pure ()
                | otherwise -> externalRuntimeInvariantFailure ProviderRuntimeInvariant "Stripe webhook Customer does not match the venue billing Customer"
            Nothing ->
                void $
                    newRecord @VenueBillingCustomer
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeCustomerId customerId
                        |> set #livemode event.stripeLivemode
                        |> createRecord

updateCheckoutAttempt :: (?modelContext :: ModelContext) => UTCTime -> Maybe Venue -> StripeWebhookEvent -> IO Bool
updateCheckoutAttempt _ Nothing _ = pure True
updateCheckoutAttempt now (Just venue) event =
    case event.stripeObjectSnapshot.stripeObjectId of
        Nothing -> pure True
        Just sessionId -> do
            maybeAttempt <-
                query @BillingCheckoutAttempt
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#stripeCheckoutSessionId, Just sessionId)
                    |> fetchOneOrNothing
            applyAttemptUpdate <- shouldApplyCheckoutAttemptUpdate event sessionId
            when applyAttemptUpdate $
                forM_ maybeAttempt \attempt -> do
                    unless (Just attempt.stripeCustomerId == snapshot.stripeObjectCustomerId && attempt.livemode == event.stripeLivemode) do
                        externalRuntimeInvariantFailure ProviderRuntimeInvariant "Stripe webhook Checkout Session does not match its local attempt"
                    case event.stripeEventType of
                        "checkout.session.async_payment_failed" ->
                            void $
                                attempt
                                    |> set #status "failed"
                                    |> set #completedAt Nothing
                                    |> set #errorCode (Just "stripe_checkout_async_payment_failed")
                                    |> set #errorSummary (Just "Stripe reported that asynchronous Checkout payment failed.")
                                    |> updateRecord
                        _ ->
                            void $
                                attempt
                                    |> set #stripeSubscriptionId snapshot.stripeObjectSubscriptionId
                                    |> set #status "completed"
                                    |> set #completedAt (Just now)
                                    |> set #errorCode Nothing
                                    |> set #errorSummary Nothing
                                    |> updateRecord
            pure applyAttemptUpdate
  where
    snapshot = event.stripeObjectSnapshot

upsertSubscription :: (?modelContext :: ModelContext) => UTCTime -> Maybe Venue -> StripeWebhookEvent -> IO ApplyResult
upsertSubscription _ Nothing _ = pure (ApplyProcessed [])
upsertSubscription now (Just venue) event = do
    let snapshot = event.stripeObjectSnapshot
    (subscriptionId, status, priceId) <-
        case (snapshot.stripeObjectSubscriptionId <|> snapshot.stripeObjectId, snapshot.stripeObjectStatus, snapshot.stripeObjectPriceId) of
            (Just subscriptionId, Just status, Just priceId) -> pure (subscriptionId, status, priceId)
            _ -> externalRuntimeInvariantFailure ProviderRuntimeInvariant "Supported Stripe subscription webhook is missing required snapshot fields"
    ensureStripeEventCustomerMatchesVenue venue event
    existing <- fetchVenueSubscriptionForStripeEvent venue event
    case existing of
        Just subscription | not (isNewerStripeEvent event subscription) -> pure (ApplyProcessed [])
        _ -> do
            let previousSubscription = matchingSubscriptionForId (Just subscriptionId) existing
            let notifications = subscriptionTransitionNotifications previousSubscription subscriptionId status snapshot
            case existing of
                Nothing ->
                    void $
                        newRecord @VenueSubscription
                            |> set #venueId (unpackId venue.id)
                            |> set #stripeSubscriptionId subscriptionId
                            |> set #stripePriceId priceId
                            |> set #livemode event.stripeLivemode
                            |> set #status status
                            |> set #currentPeriodStart (posixMaybe snapshot.stripeObjectCurrentPeriodStart)
                            |> set #currentPeriodEnd (posixMaybe snapshot.stripeObjectCurrentPeriodEnd)
                            |> set #cancelAtPeriodEnd snapshot.stripeObjectCancelAtPeriodEnd
                            |> set #lastSyncedAt now
                            |> set #lastAppliedStripeEventCreatedAt (Just event.stripeEventCreatedAt)
                            |> set #lastAppliedStripeEventId (Just event.stripeEventId)
                            |> createRecord
                Just subscription ->
                    void $
                        subscription
                            |> set #stripeSubscriptionId subscriptionId
                            |> set #stripePriceId priceId
                            |> set #livemode event.stripeLivemode
                            |> set #status status
                            |> set #currentPeriodStart (posixMaybe snapshot.stripeObjectCurrentPeriodStart)
                            |> set #currentPeriodEnd (posixMaybe snapshot.stripeObjectCurrentPeriodEnd)
                            |> set #cancelAtPeriodEnd snapshot.stripeObjectCancelAtPeriodEnd
                            |> set #lastSyncedAt now
                            |> set #lastAppliedStripeEventCreatedAt (Just event.stripeEventCreatedAt)
                            |> set #lastAppliedStripeEventId (Just event.stripeEventId)
                            |> updateRecord
            pure (ApplyProcessed notifications)

subscriptionTransitionNotifications :: Maybe VenueSubscription -> Text -> Text -> StripeObjectSnapshot -> [BillingNotification]
subscriptionTransitionNotifications previousSubscription subscriptionId currentStatus snapshot =
    troubleNotification <> recoveryNotification <> scheduledCancellationNotification <> resumedRenewalNotification <> completedCancellationNotification
  where
    wasTroubled = maybe False (isTroubledSubscriptionStatus . (.status)) previousSubscription
    isTroubled = isTroubledSubscriptionStatus currentStatus
    notification kind =
        BillingNotification
            { notificationKind = kind
            , notificationSubscriptionId = Just subscriptionId
            , notificationBillingPeriodStart = periodStart
            , notificationBillingPeriodEnd = periodEnd
            }
      where
        snapshotPeriodStart = posixMaybe snapshot.stripeObjectCurrentPeriodStart
        snapshotPeriodEnd = posixMaybe snapshot.stripeObjectCurrentPeriodEnd
        previousPeriodStart = previousSubscription >>= (.currentPeriodStart)
        previousPeriodEnd = previousSubscription >>= (.currentPeriodEnd)
        (periodStart, periodEnd)
            | kind == BillingPaymentTrouble
            , snapshotPeriodStart == previousPeriodEnd
            , isJust previousPeriodEnd =
                (previousPeriodStart, previousPeriodEnd)
            | otherwise = (snapshotPeriodStart, snapshotPeriodEnd)
    troubleNotification =
        [notification BillingPaymentTrouble | isTroubled && not wasTroubled]
    recoveryNotification =
        [notification BillingPaymentRecovered | currentStatus == "active" && wasTroubled]
    scheduledCancellationNotification =
        [ notification BillingCancellationScheduled
        | currentStatus /= "canceled"
        , snapshot.stripeObjectCancelAtPeriodEnd
        , maybe False (not . (.cancelAtPeriodEnd)) previousSubscription
        ]
    resumedRenewalNotification =
        [ notification BillingRenewalResumed
        | currentStatus `notElem` ["canceled", "incomplete_expired"]
        , not snapshot.stripeObjectCancelAtPeriodEnd
        , maybe False (.cancelAtPeriodEnd) previousSubscription
        ]
    completedCancellationNotification =
        [ notification BillingCancellationCompleted
        | currentStatus == "canceled"
        , maybe True ((/= "canceled") . (.status)) previousSubscription
        ]

isTroubledSubscriptionStatus :: Text -> Bool
isTroubledSubscriptionStatus status =
    status `elem` ["past_due", "unpaid", "incomplete_expired"]

applyInvoicePaymentFailure :: (?modelContext :: ModelContext) => Maybe Venue -> StripeWebhookEvent -> IO ApplyResult
applyInvoicePaymentFailure Nothing _ = pure (ApplyProcessed [])
applyInvoicePaymentFailure (Just venue) event = do
    ensureStripeEventCustomerMatchesVenue venue event
    case event.stripeObjectSnapshot.stripeObjectSubscriptionId of
        Nothing -> pure (ApplyProcessed [])
        Just subscriptionId -> do
            maybeSubscription <- fetchVenueSubscriptionForStripeEvent venue event
            let matchingSubscription = matchingSubscriptionForId (Just subscriptionId) maybeSubscription
            pure $
                ApplyProcessed
                    [billingNotificationFromSnapshot BillingPaymentTrouble (Just subscriptionId) event.stripeObjectSnapshot matchingSubscription]

checkoutPaymentFailureNotifications :: (?modelContext :: ModelContext) => Maybe Venue -> StripeWebhookEvent -> IO [BillingNotification]
checkoutPaymentFailureNotifications Nothing event =
    pure [billingNotificationFromSnapshot BillingCheckoutPaymentFailed event.stripeObjectSnapshot.stripeObjectSubscriptionId event.stripeObjectSnapshot Nothing]
checkoutPaymentFailureNotifications (Just venue) event = do
    maybeSubscription <- fetchVenueSubscriptionForStripeEvent venue event
    let matchingSubscription = matchingSubscriptionForId event.stripeObjectSnapshot.stripeObjectSubscriptionId maybeSubscription
    pure [billingNotificationFromSnapshot BillingCheckoutPaymentFailed event.stripeObjectSnapshot.stripeObjectSubscriptionId event.stripeObjectSnapshot matchingSubscription]

matchingSubscriptionForId :: Maybe Text -> Maybe VenueSubscription -> Maybe VenueSubscription
matchingSubscriptionForId maybeSubscriptionId maybeSubscription = do
    subscriptionId <- maybeSubscriptionId
    subscription <- maybeSubscription
    guard (subscription.stripeSubscriptionId == subscriptionId)
    pure subscription

fetchVenueSubscriptionForStripeEvent :: (?modelContext :: ModelContext) => Venue -> StripeWebhookEvent -> IO (Maybe VenueSubscription)
fetchVenueSubscriptionForStripeEvent venue event = do
    maybeSubscription <-
        query @VenueSubscription
            |> filterWhere (#venueId, unpackId venue.id)
            |> fetchOneOrNothing
    forM_ maybeSubscription \subscription ->
        unless (subscription.livemode == event.stripeLivemode) do
            externalRuntimeInvariantFailure ProviderRuntimeInvariant "Stripe webhook mode does not match the venue Subscription mode"
    pure maybeSubscription

billingNotificationFromSnapshot :: BillingNotificationKind -> Maybe Text -> StripeObjectSnapshot -> Maybe VenueSubscription -> BillingNotification
billingNotificationFromSnapshot kind maybeSubscriptionId snapshot maybeSubscription =
    BillingNotification
        { notificationKind = kind
        , notificationSubscriptionId = maybeSubscriptionId
        , notificationBillingPeriodStart = posixMaybe snapshot.stripeObjectCurrentPeriodStart <|> (maybeSubscription >>= (.currentPeriodStart))
        , notificationBillingPeriodEnd = posixMaybe snapshot.stripeObjectCurrentPeriodEnd <|> (maybeSubscription >>= (.currentPeriodEnd))
        }

ensureStripeEventCustomerMatchesVenue :: (?modelContext :: ModelContext) => Venue -> StripeWebhookEvent -> IO ()
ensureStripeEventCustomerMatchesVenue venue event =
    forM_ event.stripeObjectSnapshot.stripeObjectCustomerId \customerId -> do
        maybeCustomer <-
            query @VenueBillingCustomer
                |> filterWhere (#venueId, unpackId venue.id)
                |> fetchOneOrNothing
        case maybeCustomer of
            Just customer
                | customer.stripeCustomerId == customerId && customer.livemode == event.stripeLivemode -> pure ()
                | otherwise -> externalRuntimeInvariantFailure ProviderRuntimeInvariant "Stripe webhook subscription Customer does not match the venue billing Customer"
            Nothing -> pure ()

shouldApplyCheckoutAttemptUpdate :: (?modelContext :: ModelContext) => StripeWebhookEvent -> Text -> IO Bool
shouldApplyCheckoutAttemptUpdate event sessionId = do
    priorEvents <-
        query @BillingEvent
            |> filterWhere (#providerObjectType, Just "checkout.session")
            |> filterWhere (#providerObjectId, Just sessionId)
            |> filterWhere (#status, "processed")
            |> fetch
    pure (not (any (`isStripeEventNewerThan` event) priorEvents))

isStripeEventNewerThan :: BillingEvent -> StripeWebhookEvent -> Bool
isStripeEventNewerThan billingEvent event =
    case billingEvent.stripeCreatedAt of
        Just createdAt -> (createdAt, billingEvent.stripeEventId) > (event.stripeEventCreatedAt, event.stripeEventId)
        Nothing -> False

isNewerStripeEvent :: StripeWebhookEvent -> VenueSubscription -> Bool
isNewerStripeEvent event subscription =
    case (subscription.lastAppliedStripeEventCreatedAt, subscription.lastAppliedStripeEventId) of
        (Nothing, Nothing) -> True
        (Just appliedAt, Just appliedId) ->
            (event.stripeEventCreatedAt, event.stripeEventId) > (appliedAt, appliedId)
        _ -> externalRuntimeInvariantFailure ProviderRuntimeInvariant "Venue Subscription has an incomplete Stripe event ordering cursor"

isCheckoutPaymentFailure :: StripeWebhookEvent -> Bool
isCheckoutPaymentFailure event =
    event.stripeEventType == "checkout.session.async_payment_failed"

resolveAndLockStripeEventVenue :: (?modelContext :: ModelContext) => StripeWebhookEvent -> IO (Maybe Venue)
resolveAndLockStripeEventVenue event = do
    maybeVenue <- resolveStripeEventVenue event
    forM_ maybeVenue (lockVenueForBilling . unpackId . (.id))
    resolveStripeEventVenue event

resolveStripeEventVenue :: (?modelContext :: ModelContext) => StripeWebhookEvent -> IO (Maybe Venue)
resolveStripeEventVenue event =
    resolveVenueFromText (event.stripeObjectSnapshot.stripeObjectMetadataVenueId <|> event.stripeObjectSnapshot.stripeObjectClientReferenceId) >>= \case
        Just venue -> pure (Just venue)
        Nothing ->
            case event.stripeObjectSnapshot.stripeObjectCustomerId of
                Nothing -> pure Nothing
                Just customerId -> do
                    maybeCustomer <-
                        query @VenueBillingCustomer
                            |> filterWhere (#stripeCustomerId, customerId)
                            |> fetchOneOrNothing
                    case maybeCustomer of
                        Nothing       -> pure Nothing
                        Just customer -> Just <$> fetch (Id customer.venueId :: Id Venue)

resolveVenueFromText :: (?modelContext :: ModelContext) => Maybe Text -> IO (Maybe Venue)
resolveVenueFromText Nothing = pure Nothing
resolveVenueFromText (Just rawVenueId) =
    case UUID.fromText rawVenueId of
        Nothing        -> pure Nothing
        Just venueUuid -> fetchOneOrNothing (Id venueUuid :: Id Venue)

posixMaybe :: Maybe Integer -> Maybe UTCTime
posixMaybe = fmap (posixSecondsToUTCTime . fromInteger)

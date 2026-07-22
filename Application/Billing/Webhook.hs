module Application.Billing.Webhook
    ( BillingWebhookResult (..)
    , StripeWebhookEvent (..)
    , handleStripeWebhookPayload
    , parseStripeWebhookEvent
    , processStripeWebhookEvent
    )
where

import Application.Billing.Notifications (enqueueBillingNotifications)
import Application.Billing.Stripe (StripeMode (..), StripeSubscription (..),
                                   pinnedStripeApiVersion)
import Control.Exception (try)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString.Lazy as LByteString
import qualified Data.Text as Text
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
    , stripeLivemode       :: !Bool
    , stripeApiVersion     :: !(Maybe Text)
    , stripeObjectSnapshot :: !StripeObjectSnapshot
    }
    deriving (Eq, Show)

data StripeObjectSnapshot = StripeObjectSnapshot
    { stripeObjectType               :: !(Maybe Text)
    , stripeObjectId                 :: !(Maybe Text)
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
            dataObject <- object Aeson..: "data"
            stripeObject <- dataObject Aeson..: "object"
            StripeWebhookEvent
                <$> object Aeson..: "id"
                <*> object Aeson..: "type"
                <*> object Aeson..: "livemode"
                <*> object Aeson..:? "api_version"
                <*> parseStripeObjectSnapshot stripeObject

parseStripeObjectSnapshot :: Aeson.Value -> AesonTypes.Parser StripeObjectSnapshot
parseStripeObjectSnapshot stripeObject =
    Aeson.withObject "StripeObjectSnapshot" (parseObject stripeObject) stripeObject
  where
    parseObject originalValue object = do
        metadata <- object Aeson..:? "metadata" Aeson..!= Aeson.Object mempty
        objectType <- object Aeson..:? "object"
        subscriptionContract <-
            case objectType of
                Just "subscription" -> Just <$> (Aeson.parseJSON originalValue :: AesonTypes.Parser StripeSubscription)
                _ -> pure Nothing
        objectId <- object Aeson..:? "id"
        customerId <- object Aeson..:? "customer"
        subscriptionId <- object Aeson..:? "subscription"
        clientReferenceId <- object Aeson..:? "client_reference_id"
        metadataVenueId <- parseMetadataVenueId metadata
        status <- object Aeson..:? "status"
        priceId <- parseObjectPriceId object
        currentPeriodStart <- object Aeson..:? "current_period_start"
        currentPeriodEnd <- object Aeson..:? "current_period_end"
        cancelAtPeriodEnd <- object Aeson..:? "cancel_at_period_end" Aeson..!= False
        pure
            StripeObjectSnapshot
                { stripeObjectType = objectType
                , stripeObjectId = objectId
                , stripeObjectCustomerId = maybe customerId (Just . (.stripeSubscriptionCustomerId)) subscriptionContract
                , stripeObjectSubscriptionId = maybe subscriptionId (Just . (.stripeSubscriptionId)) subscriptionContract
                , stripeObjectClientReferenceId = clientReferenceId
                , stripeObjectMetadataVenueId = metadataVenueId
                , stripeObjectStatus = maybe status (Just . (.stripeSubscriptionStatus)) subscriptionContract
                , stripeObjectPriceId = maybe priceId (Just . (.stripeSubscriptionPriceId)) subscriptionContract
                , stripeObjectCurrentPeriodStart = maybe currentPeriodStart (Just . (.stripeSubscriptionCurrentPeriodStart)) subscriptionContract
                , stripeObjectCurrentPeriodEnd = maybe currentPeriodEnd (Just . (.stripeSubscriptionCurrentPeriodEnd)) subscriptionContract
                , stripeObjectCancelAtPeriodEnd = maybe cancelAtPeriodEnd (.stripeSubscriptionCancelAtPeriodEnd) subscriptionContract
                }

parseMetadataVenueId :: Aeson.Value -> AesonTypes.Parser (Maybe Text)
parseMetadataVenueId =
    Aeson.withObject "StripeMetadata" (Aeson..:? "venue_id")

parseObjectPriceId :: Aeson.Object -> AesonTypes.Parser (Maybe Text)
parseObjectPriceId object =
    case AesonKeyMap.lookup (AesonKey.fromString "items") object of
        Nothing -> pure Nothing
        Just itemsValue ->
            parseItemsPriceId itemsValue

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
            Just (Aeson.Object priceObject) ->
                priceObject Aeson..:? "id"
            _ -> pure Nothing

parseStripeWebhookEvent :: LByteString.ByteString -> Either Text StripeWebhookEvent
parseStripeWebhookEvent rawBody =
    case Aeson.eitherDecode rawBody of
        Left err    -> Left ("Unable to decode Stripe webhook event: " <> cs err)
        Right event -> Right event

handleStripeWebhookPayload :: (?modelContext :: ModelContext) => StripeMode -> LByteString.ByteString -> IO (Either Text BillingWebhookResult)
handleStripeWebhookPayload expectedMode rawBody =
    case parseStripeWebhookEvent rawBody >>= validateStripeWebhookContract expectedMode of
        Left err    -> pure (Left err)
        Right event -> Right <$> processStripeWebhookEvent event

validateStripeWebhookContract :: StripeMode -> StripeWebhookEvent -> Either Text StripeWebhookEvent
validateStripeWebhookContract expectedMode event = do
    unless (event.stripeApiVersion == Just pinnedStripeApiVersion) do
        Left "Stripe webhook API version does not match the pinned billing contract"
    unless (event.stripeLivemode == stripeModeIsLive expectedMode) do
        Left "Stripe webhook mode does not match the configured billing mode"
    pure event
  where
    stripeModeIsLive StripeTestMode = False
    stripeModeIsLive StripeLiveMode = True

processStripeWebhookEvent :: (?modelContext :: ModelContext) => StripeWebhookEvent -> IO BillingWebhookResult
processStripeWebhookEvent event = do
    existing <- query @BillingEvent |> filterWhere (#stripeEventId, event.stripeEventId) |> fetchOneOrNothing
    case existing of
        Just billingEvent -> pure (BillingWebhookDuplicate billingEvent)
        Nothing ->
            withTransaction do
                now <- getCurrentTime
                maybeVenue <- resolveStripeEventVenue event
                billingEvent <-
                    createBillingEventRecord event maybeVenue
                try (applyStripeEvent now event maybeVenue billingEvent) >>= \case
                    Left (exception :: SomeException) -> do
                        failedEvent <-
                            billingEvent
                                |> set #status "failed"
                                |> set #errorSummary (Just (Text.take 1000 (cs (displayException exception))))
                                |> updateRecord
                        pure (BillingWebhookProcessed failedEvent)
                    Right ApplyIgnored -> do
                        ignoredEvent <-
                            billingEvent
                                |> set #status "ignored"
                                |> updateRecord
                        pure (BillingWebhookIgnored ignoredEvent)
                    Right ApplyProcessed -> do
                        processedEvent <-
                            billingEvent
                                |> set #status "processed"
                                |> set #processedAt (Just now)
                                |> updateRecord
                        maybeNotifyBillingProblem event maybeVenue processedEvent
                        pure (BillingWebhookProcessed processedEvent)

createBillingEventRecord :: (?modelContext :: ModelContext) => StripeWebhookEvent -> Maybe Venue -> IO BillingEvent
createBillingEventRecord event maybeVenue =
    newRecord @BillingEvent
        |> set #stripeEventId event.stripeEventId
        |> set #eventType event.stripeEventType
        |> set #livemode event.stripeLivemode
        |> set #apiVersion event.stripeApiVersion
        |> set #providerObjectType event.stripeObjectSnapshot.stripeObjectType
        |> set #providerObjectId event.stripeObjectSnapshot.stripeObjectId
        |> set #venueId (unpackId . (.id) <$> maybeVenue)
        |> set #stripeCustomerId event.stripeObjectSnapshot.stripeObjectCustomerId
        |> set #stripeSubscriptionId event.stripeObjectSnapshot.stripeObjectSubscriptionId
        |> createRecord

data ApplyResult = ApplyProcessed | ApplyIgnored
    deriving (Eq, Show)

applyStripeEvent :: (?modelContext :: ModelContext) => UTCTime -> StripeWebhookEvent -> Maybe Venue -> BillingEvent -> IO ApplyResult
applyStripeEvent now event maybeVenue _billingEvent =
    case event.stripeEventType of
        "checkout.session.completed" -> ensureCheckoutCustomer maybeVenue event
        "checkout.session.async_payment_succeeded" -> ensureCheckoutCustomer maybeVenue event
        "checkout.session.async_payment_failed" -> ensureCheckoutCustomer maybeVenue event
        "customer.subscription.created" -> upsertSubscription now maybeVenue event
        "customer.subscription.updated" -> upsertSubscription now maybeVenue event
        "customer.subscription.deleted" -> upsertSubscription now maybeVenue event
        "invoice.payment_failed" -> pure ApplyProcessed
        _ -> pure ApplyIgnored

ensureCheckoutCustomer :: (?modelContext :: ModelContext) => Maybe Venue -> StripeWebhookEvent -> IO ApplyResult
ensureCheckoutCustomer Nothing _ = pure ApplyProcessed
ensureCheckoutCustomer (Just venue) event = do
    forM_ event.stripeObjectSnapshot.stripeObjectCustomerId \customerId -> do
        existing <-
            query @VenueBillingCustomer
                |> filterWhere (#venueId, unpackId venue.id)
                |> fetchOneOrNothing
        case existing of
            Just _ -> pure ()
            Nothing ->
                void $
                    newRecord @VenueBillingCustomer
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeCustomerId customerId
                        |> createRecord
    pure ApplyProcessed

upsertSubscription :: (?modelContext :: ModelContext) => UTCTime -> Maybe Venue -> StripeWebhookEvent -> IO ApplyResult
upsertSubscription _ Nothing _ = pure ApplyProcessed
upsertSubscription now (Just venue) event = do
    let snapshot = event.stripeObjectSnapshot
    case (snapshot.stripeObjectSubscriptionId <|> snapshot.stripeObjectId, snapshot.stripeObjectStatus) of
        (Just subscriptionId, Just status) -> do
            let priceId = fromMaybe "unknown" snapshot.stripeObjectPriceId
            existing <-
                query @VenueSubscription
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> fetchOneOrNothing
            case existing of
                Nothing ->
                    void $
                        newRecord @VenueSubscription
                            |> set #venueId (unpackId venue.id)
                            |> set #stripeSubscriptionId subscriptionId
                            |> set #stripePriceId priceId
                            |> set #status status
                            |> set #currentPeriodStart (posixMaybe snapshot.stripeObjectCurrentPeriodStart)
                            |> set #currentPeriodEnd (posixMaybe snapshot.stripeObjectCurrentPeriodEnd)
                            |> set #cancelAtPeriodEnd snapshot.stripeObjectCancelAtPeriodEnd
                            |> set #lastSyncedAt now
                            |> createRecord
                Just subscription ->
                    void $
                        subscription
                            |> set #stripeSubscriptionId subscriptionId
                            |> set #stripePriceId priceId
                            |> set #status status
                            |> set #currentPeriodStart (posixMaybe snapshot.stripeObjectCurrentPeriodStart)
                            |> set #currentPeriodEnd (posixMaybe snapshot.stripeObjectCurrentPeriodEnd)
                            |> set #cancelAtPeriodEnd snapshot.stripeObjectCancelAtPeriodEnd
                            |> set #lastSyncedAt now
                            |> updateRecord
            pure ApplyProcessed
        _ ->
            pure ApplyProcessed

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
posixMaybe =
    fmap (posixSecondsToUTCTime . fromInteger)

maybeNotifyBillingProblem :: (?modelContext :: ModelContext) => StripeWebhookEvent -> Maybe Venue -> BillingEvent -> IO ()
maybeNotifyBillingProblem event maybeVenue billingEvent =
    case (maybeVenue, billingProblemKind event) of
        (Just venue, Just notificationKind) -> void (enqueueBillingNotifications venue billingEvent notificationKind)
        _                                  -> pure ()

billingProblemKind :: StripeWebhookEvent -> Maybe Text
billingProblemKind event
    | event.stripeEventType == "invoice.payment_failed" = Just "payment_failed"
    | event.stripeEventType == "checkout.session.async_payment_failed" = Just "async_payment_failed"
    | event.stripeEventType `elem` ["customer.subscription.created", "customer.subscription.updated", "customer.subscription.deleted"] =
        case event.stripeObjectSnapshot.stripeObjectStatus of
            Just status | status `elem` ["past_due", "canceled", "unpaid", "incomplete_expired"] -> Just status
            _ -> Nothing
    | otherwise = Nothing

module Application.Billing.Stripe
    ( StripeCheckoutSession (..)
    , StripeClient (..)
    , StripeClientError (..)
    , StripeConfig (..)
    , StripeCustomer (..)
    , StripeDeploymentControls (..)
    , StripeHttpRequest (..)
    , StripeMode (..)
    , StripePortalSession (..)
    , StripePrice (..)
    , StripeRecurring (..)
    , StripeRequestBody (..)
    , StripeRequestBaseUrls (..)
    , StripeSubscription (..)
    , StripeWebhookSignature (..)
    , billingIdempotencyKey
    , buildCreateCheckoutSessionRequest
    , buildCreateCustomerRequest
    , buildCreatePortalSessionRequest
    , buildListPricesRequest
    , buildRetrieveCheckoutSessionRequest
    , buildRetrievePriceRequest
    , buildRetrieveSubscriptionRequest
    , currentStripeClient
    , defaultPriceLookupKey
    , defaultStripeRequestBaseUrls
    , pinnedStripeApiVersion
    , readStripeConfig
    , readStripeDeploymentControls
    , stripeClientErrorText
    , stripeClientWithTransport
    , stripeModeIsLive
    , stripeWebhookSignedPayload
    , validateStripeCheckoutRedirectUrl
    , validateStripePortalRedirectUrl
    , validateVenueMonthlyPrice
    , verifyStripeWebhookSignature
    , verifyStripeWebhookSignatureAt
    , withStripeClientForTest
    , withStripeConfigForTest
    )
where

import Control.Applicative ((<|>))
import qualified Control.Exception as Exception
import qualified "crypton" Crypto.Hash as Hash
import "crypton" Crypto.MAC.HMAC (HMAC, hmac)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteArray as ByteArray
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LByteString
import qualified Data.Char as Char
import qualified Data.IORef as IORef
import qualified Data.List as List
import qualified Data.Text as Text hiding (show)
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Text.IO as TextIO
import Data.Time.Clock.POSIX (POSIXTime, getPOSIXTime)
import IHP.Prelude
import qualified Network.HTTP.Client as Http
import Network.HTTP.Simple
import Network.HTTP.Types.Header (HeaderName)
import qualified Network.HTTP.Types.URI as URI
import System.Environment (lookupEnv)
import qualified System.IO.Error as IOError
import System.IO.Unsafe (unsafePerformIO)
import qualified System.Timeout as Timeout
import Text.Read (readMaybe)

defaultPriceLookupKey :: Text
defaultPriceLookupKey = "bepis_venue_monthly_aud_100"

pinnedStripeApiVersion :: Text
pinnedStripeApiVersion = "2026-06-24.dahlia"

stripeHttpTimeoutMicroseconds :: Int
stripeHttpTimeoutMicroseconds = 15000000

data StripeMode
    = StripeTestMode
    | StripeLiveMode
    deriving (Eq, Show)

data StripeDeploymentControls = StripeDeploymentControls
    { stripeBillingEnabled         :: !Bool
    , stripeCheckoutEnabled        :: !Bool
    , stripeOwnerNavigationVisible :: !Bool
    }
    deriving (Eq, Show)

data StripeConfig = StripeConfig
    { secretKey                :: !Text
    , webhookSecret            :: !Text
    , priceLookupKey           :: !(Maybe Text)
    , priceId                  :: !(Maybe Text)
    , appBaseUrl               :: !Text
    , stripeMode               :: !StripeMode
    , stripeDeploymentControls :: !StripeDeploymentControls
    }
    deriving (Eq)

data StripeRequestBaseUrls = StripeRequestBaseUrls
    { stripeApiBaseUrl :: !Text
    }
    deriving (Eq, Show)

defaultStripeRequestBaseUrls :: StripeRequestBaseUrls
defaultStripeRequestBaseUrls =
    StripeRequestBaseUrls
        { stripeApiBaseUrl = "https://api.stripe.com"
        }

data StripeRequestBody
    = StripeFormBody [(ByteString, ByteString)]
    deriving (Eq, Show)

data StripeHttpRequest = StripeHttpRequest
    { stripeRequestMethod              :: !ByteString
    , stripeRequestUrl                 :: !Text
    , stripeRequestHeaders             :: ![(HeaderName, ByteString)]
    , stripeRequestBody                :: !(Maybe StripeRequestBody)
    , stripeRequestTimeoutMicroseconds :: !Int
    }
    deriving (Eq)

data StripeRecurring = StripeRecurring
    { interval      :: !Text
    , intervalCount :: !Int
    , usageType     :: !(Maybe Text)
    }
    deriving (Eq, Show)

instance Aeson.FromJSON StripeRecurring where
    parseJSON = Aeson.withObject "StripeRecurring" \object ->
        StripeRecurring
            <$> object Aeson..: "interval"
            <*> object Aeson..: "interval_count"
            <*> object Aeson..:? "usage_type"

data StripePrice = StripePrice
    { stripePriceId       :: !Text
    , stripePriceLivemode :: !Bool
    , active              :: !Bool
    , currency            :: !Text
    , unitAmount          :: !(Maybe Int)
    , priceType           :: !Text
    , recurring           :: !(Maybe StripeRecurring)
    }
    deriving (Eq, Show)

instance Aeson.FromJSON StripePrice where
    parseJSON = Aeson.withObject "StripePrice" \object ->
        StripePrice
            <$> object Aeson..: "id"
            <*> object Aeson..: "livemode"
            <*> object Aeson..: "active"
            <*> object Aeson..: "currency"
            <*> object Aeson..:? "unit_amount"
            <*> object Aeson..: "type"
            <*> object Aeson..:? "recurring"

newtype StripePriceList = StripePriceList { prices :: [StripePrice] }
    deriving (Eq, Show)

instance Aeson.FromJSON StripePriceList where
    parseJSON = Aeson.withObject "StripePriceList" \object ->
        StripePriceList <$> object Aeson..: "data"

data StripeCustomer = StripeCustomer
    { stripeCustomerId       :: !Text
    , stripeCustomerLivemode :: !Bool
    }
    deriving (Eq, Show)

instance Aeson.FromJSON StripeCustomer where
    parseJSON = Aeson.withObject "StripeCustomer" \object ->
        StripeCustomer
            <$> object Aeson..: "id"
            <*> object Aeson..: "livemode"

data StripeCheckoutSession = StripeCheckoutSession
    { stripeCheckoutSessionId      :: !Text
    , stripeCheckoutSessionUrl     :: !(Maybe Text)
    , stripeCheckoutCustomerId     :: !(Maybe Text)
    , stripeCheckoutSubscriptionId :: !(Maybe Text)
    , stripeCheckoutLivemode       :: !Bool
    , stripeCheckoutMode           :: !Text
    , stripeCheckoutStatus         :: !Text
    }
    deriving (Eq, Show)

instance Aeson.FromJSON StripeCheckoutSession where
    parseJSON = Aeson.withObject "StripeCheckoutSession" \object ->
        StripeCheckoutSession
            <$> object Aeson..: "id"
            <*> object Aeson..:? "url"
            <*> object Aeson..:? "customer"
            <*> object Aeson..:? "subscription"
            <*> object Aeson..: "livemode"
            <*> object Aeson..: "mode"
            <*> object Aeson..: "status"

data StripePortalSession = StripePortalSession
    { stripePortalSessionId       :: !Text
    , stripePortalSessionUrl      :: !Text
    , stripePortalSessionLivemode :: !Bool
    }
    deriving (Eq, Show)

instance Aeson.FromJSON StripePortalSession where
    parseJSON = Aeson.withObject "StripePortalSession" \object ->
        StripePortalSession
            <$> object Aeson..: "id"
            <*> object Aeson..: "url"
            <*> object Aeson..: "livemode"

data StripeSubscription = StripeSubscription
    { stripeSubscriptionId                 :: !Text
    , stripeSubscriptionCustomerId         :: !Text
    , stripeSubscriptionLivemode           :: !Bool
    , stripeSubscriptionStatus             :: !Text
    , stripeSubscriptionPriceId            :: !Text
    , stripeSubscriptionPriceLivemode      :: !Bool
    , stripeSubscriptionCurrentPeriodStart :: !Integer
    , stripeSubscriptionCurrentPeriodEnd   :: !Integer
    , stripeSubscriptionCancelAtPeriodEnd  :: !Bool
    }
    deriving (Eq, Show)

instance Aeson.FromJSON StripeSubscription where
    parseJSON = Aeson.withObject "StripeSubscription" \object -> do
        item <- object Aeson..: "items" >>= parseSingleSubscriptionItem
        unless (item.subscriptionItemQuantity == 1) (fail "Stripe Subscription item quantity must be one")
        case validateVenueMonthlyPrice item.subscriptionItemPrice of
            Left message -> fail (cs message)
            Right _      -> pure ()
        StripeSubscription
            <$> object Aeson..: "id"
            <*> object Aeson..: "customer"
            <*> object Aeson..: "livemode"
            <*> object Aeson..: "status"
            <*> pure item.subscriptionItemPrice.stripePriceId
            <*> pure item.subscriptionItemPrice.stripePriceLivemode
            <*> pure item.subscriptionItemCurrentPeriodStart
            <*> pure item.subscriptionItemCurrentPeriodEnd
            <*> object Aeson..: "cancel_at_period_end"

data StripeSubscriptionItem = StripeSubscriptionItem
    { subscriptionItemPrice              :: !StripePrice
    , subscriptionItemQuantity           :: !Int
    , subscriptionItemCurrentPeriodStart :: !Integer
    , subscriptionItemCurrentPeriodEnd   :: !Integer
    }

instance Aeson.FromJSON StripeSubscriptionItem where
    parseJSON = Aeson.withObject "StripeSubscriptionItem" \object ->
        StripeSubscriptionItem
            <$> object Aeson..: "price"
            <*> object Aeson..: "quantity"
            <*> object Aeson..: "current_period_start"
            <*> object Aeson..: "current_period_end"

parseSingleSubscriptionItem :: Aeson.Value -> AesonTypes.Parser StripeSubscriptionItem
parseSingleSubscriptionItem = Aeson.withObject "StripeSubscriptionItems" \object -> do
    items <- object Aeson..: "data"
    case items of
        [item] -> Aeson.parseJSON item
        []     -> fail "Stripe Subscription must contain one fixed-price item"
        _      -> fail "Stripe Subscription must not contain multiple items"

data StripeClientError
    = StripeHttpError !Text
    | StripeJsonError !Text
    deriving (Eq, Show)

stripeClientErrorText :: StripeClientError -> Text
stripeClientErrorText = \case
    StripeHttpError _ -> "Stripe is temporarily unavailable. Try again."
    StripeJsonError _ -> "Stripe returned an unexpected response. Try again."

data StripeClient = StripeClient
    { listPrices :: StripeConfig -> IO (Either StripeClientError [StripePrice])
    , retrievePrice :: StripeConfig -> Text -> IO (Either StripeClientError StripePrice)
    , createCustomer :: StripeConfig -> Text -> Text -> IO (Either StripeClientError StripeCustomer)
    , createCheckoutSession :: StripeConfig -> Text -> Text -> Text -> Text -> Text -> IO (Either StripeClientError StripeCheckoutSession)
    , retrieveCheckoutSession :: StripeConfig -> Text -> IO (Either StripeClientError StripeCheckoutSession)
    , createPortalSession :: StripeConfig -> Text -> Text -> Text -> IO (Either StripeClientError StripePortalSession)
    , retrieveSubscription :: StripeConfig -> Text -> IO (Either StripeClientError StripeSubscription)
    }

defaultStripeClient :: StripeClient
defaultStripeClient = stripeClientWithTransport sendStripeRawRequest

stripeClientRef :: IORef.IORef StripeClient
stripeClientRef = unsafePerformIO (IORef.newIORef defaultStripeClient)
{-# NOINLINE stripeClientRef #-}

stripeConfigOverrideRef :: IORef.IORef (Maybe (Either Text StripeConfig))
stripeConfigOverrideRef = unsafePerformIO (IORef.newIORef Nothing)
{-# NOINLINE stripeConfigOverrideRef #-}

currentStripeClient :: IO StripeClient
currentStripeClient = IORef.readIORef stripeClientRef

withStripeClientForTest :: StripeClient -> IO a -> IO a
withStripeClientForTest client action =
    Exception.bracket
        (IORef.atomicModifyIORef' stripeClientRef \old -> (client, old))
        (IORef.writeIORef stripeClientRef)
        (const action)

withStripeConfigForTest :: Either Text StripeConfig -> IO a -> IO a
withStripeConfigForTest configResult action =
    Exception.bracket
        (IORef.atomicModifyIORef' stripeConfigOverrideRef \old -> (Just configResult, old))
        (IORef.writeIORef stripeConfigOverrideRef)
        (const action)

stripeClientWithTransport :: (StripeHttpRequest -> IO (Either StripeClientError LByteString.ByteString)) -> StripeClient
stripeClientWithTransport transport =
    StripeClient
        { listPrices = \config -> do
            result <- fmap prices <$> sendStripeJsonRequestWith transport "Stripe price lookup" (buildListPricesRequest config)
            pure (result >>= mapM (validateStripeResponseMode "price lookup" config (.stripePriceLivemode)))
        , retrievePrice = \config price ->
            sendModeCheckedStripeJsonRequest transport "price retrieve" config (.stripePriceLivemode) (buildRetrievePriceRequest config price)
        , createCustomer = \config venueId venueName ->
            sendModeCheckedStripeJsonRequest transport "customer create" config (.stripeCustomerLivemode) (buildCreateCustomerRequest config venueId venueName)
        , createCheckoutSession = \config venueId customerId price successUrl cancelUrl ->
            sendModeCheckedStripeJsonRequest transport "checkout session create" config (.stripeCheckoutLivemode) (buildCreateCheckoutSessionRequest config venueId customerId price successUrl cancelUrl)
        , retrieveCheckoutSession = \config sessionId ->
            sendModeCheckedStripeJsonRequest transport "checkout session retrieve" config (.stripeCheckoutLivemode) (buildRetrieveCheckoutSessionRequest config sessionId)
        , createPortalSession = \config venueId customerId returnUrl ->
            sendModeCheckedStripeJsonRequest transport "portal session create" config (.stripePortalSessionLivemode) (buildCreatePortalSessionRequest config venueId customerId returnUrl)
        , retrieveSubscription = \config subscriptionId -> do
            result <- sendModeCheckedStripeJsonRequest transport "subscription retrieve" config (.stripeSubscriptionLivemode) (buildRetrieveSubscriptionRequest config subscriptionId)
            pure (result >>= validateStripeResponseMode "subscription item price" config (.stripeSubscriptionPriceLivemode))
        }

sendModeCheckedStripeJsonRequest
    :: Aeson.FromJSON value
    => (StripeHttpRequest -> IO (Either StripeClientError LByteString.ByteString))
    -> Text
    -> StripeConfig
    -> (value -> Bool)
    -> StripeHttpRequest
    -> IO (Either StripeClientError value)
sendModeCheckedStripeJsonRequest transport label config responseLivemode request = do
    result <- sendStripeJsonRequestWith transport ("Stripe " <> label) request
    pure (result >>= validateStripeResponseMode label config responseLivemode)

validateStripeResponseMode :: Text -> StripeConfig -> (value -> Bool) -> value -> Either StripeClientError value
validateStripeResponseMode label config responseLivemode value =
    if responseLivemode value == stripeModeIsLive config.stripeMode
        then Right value
        else
            Left
                ( StripeJsonError
                    ( "Stripe "
                        <> label
                        <> " returned "
                        <> stripeModeName (if responseLivemode value then StripeLiveMode else StripeTestMode)
                        <> "-mode data to a "
                        <> stripeModeName config.stripeMode
                        <> "-mode integration"
                    )
                )

stripeModeIsLive :: StripeMode -> Bool
stripeModeIsLive StripeTestMode = False
stripeModeIsLive StripeLiveMode = True

stripeModeName :: StripeMode -> Text
stripeModeName StripeTestMode = "test"
stripeModeName StripeLiveMode = "live"

readStripeConfig :: IO (Either Text StripeConfig)
readStripeConfig = do
    IORef.readIORef stripeConfigOverrideRef >>= \case
        Just configResult -> pure configResult
        Nothing ->
            readStripeDeploymentControls >>= \case
                Left err -> pure (Left err)
                Right stripeDeploymentControls
                    | not stripeDeploymentControls.stripeBillingEnabled ->
                        pure (Left "Stripe billing is disabled")
                    | otherwise ->
                        readStripeMode >>= \case
                            Left err -> pure (Left err)
                            Right stripeMode -> readEnabledStripeConfig stripeDeploymentControls stripeMode

readEnabledStripeConfig :: StripeDeploymentControls -> StripeMode -> IO (Either Text StripeConfig)
readEnabledStripeConfig stripeDeploymentControls stripeMode = do
    maybeSecretKey <- readSecret "STRIPE_SECRET_KEY_FILE" "STRIPE_SECRET_KEY"
    maybeWebhookSecret <- readSecret "STRIPE_WEBHOOK_SECRET_FILE" "STRIPE_WEBHOOK_SECRET"
    maybeLookupKey <- cleanMaybe <$> lookupEnvText "STRIPE_PRICE_LOOKUP_KEY"
    maybePriceId <- cleanMaybe <$> lookupEnvText "STRIPE_PRICE_ID"
    appBaseUrl <- fromMaybe "http://localhost:8000" . cleanMaybe <$> lookupEnvText "APP_BASE_URL"
    pure case (maybeSecretKey, maybeWebhookSecret) of
        (Right (Just secretKey), Right (Just webhookSecret)) -> do
            validateStripeSecretKey stripeMode secretKey
            validateStripeWebhookSecret webhookSecret
            validateStripeAppBaseUrl stripeMode appBaseUrl
            Right
                StripeConfig
                    { secretKey
                    , webhookSecret
                    , priceLookupKey = maybeLookupKey <|> if isJust maybePriceId then Nothing else Just defaultPriceLookupKey
                    , priceId = maybePriceId
                    , appBaseUrl
                    , stripeMode
                    , stripeDeploymentControls
                    }
        (Left err, _) -> Left err
        (_, Left err) -> Left err
        _ -> Left "Stripe is not configured. Set STRIPE_SECRET_KEY_FILE and STRIPE_WEBHOOK_SECRET_FILE, or dev/test STRIPE_SECRET_KEY and STRIPE_WEBHOOK_SECRET."

validateStripeSecretKey :: StripeMode -> Text -> Either Text ()
validateStripeSecretKey StripeTestMode key
    | any (`Text.isPrefixOf` key) ["sk_test_", "rk_test_"] = Right ()
    | otherwise = Left "Stripe test mode requires a test secret key"
validateStripeSecretKey StripeLiveMode key
    | any (`Text.isPrefixOf` key) ["rk_live_", "sk_live_"] = Right ()
    | otherwise = Left "Stripe live mode requires a live secret key"

validateStripeWebhookSecret :: Text -> Either Text ()
validateStripeWebhookSecret secret
    | "whsec_" `Text.isPrefixOf` secret = Right ()
    | otherwise = Left "Stripe webhook signing secret must start with whsec_"

validateStripeAppBaseUrl :: StripeMode -> Text -> Either Text ()
validateStripeAppBaseUrl StripeTestMode _ = Right ()
validateStripeAppBaseUrl StripeLiveMode baseUrl
    | "https://" `Text.isPrefixOf` Text.toLower baseUrl = Right ()
    | otherwise = Left "Stripe live mode requires an HTTPS APP_BASE_URL"

readStripeDeploymentControls :: IO (Either Text StripeDeploymentControls)
readStripeDeploymentControls =
    IORef.readIORef stripeConfigOverrideRef >>= \case
        Just configResult -> pure (fmap (.stripeDeploymentControls) configResult)
        Nothing -> readStripeDeploymentControlsFromEnv

readStripeDeploymentControlsFromEnv :: IO (Either Text StripeDeploymentControls)
readStripeDeploymentControlsFromEnv = do
    billingEnabled <- readStripeBoolean "STRIPE_BILLING_ENABLED"
    checkoutEnabled <- readStripeBoolean "STRIPE_CHECKOUT_ENABLED"
    ownerNavigationVisible <- readStripeBoolean "STRIPE_OWNER_NAVIGATION_VISIBLE"
    pure $
        StripeDeploymentControls
            <$> billingEnabled
            <*> checkoutEnabled
            <*> ownerNavigationVisible

readStripeBoolean :: String -> IO (Either Text Bool)
readStripeBoolean name = do
    value <- fmap Text.toLower . cleanMaybe <$> lookupEnvText name
    pure case value of
        Nothing      -> Right False
        Just "true"  -> Right True
        Just "false" -> Right False
        Just _       -> Left (cs name <> " must be true or false")

readStripeMode :: IO (Either Text StripeMode)
readStripeMode = do
    value <- fmap Text.toLower . cleanMaybe <$> lookupEnvText "STRIPE_MODE"
    pure case value of
        Just "test" -> Right StripeTestMode
        Just "live" -> Right StripeLiveMode
        _           -> Left "STRIPE_MODE must be explicitly set to test or live"

readSecret :: String -> String -> IO (Either Text (Maybe Text))
readSecret fileEnv valueEnv = do
    maybeFile <- cleanMaybe <$> lookupEnvText fileEnv
    case maybeFile of
        Just filePath ->
            fmap (Right . cleanText)
                (TextIO.readFile (cs filePath))
                `Exception.catch` \(err :: IOError.IOError) ->
                    pure (Left ("Unable to read Stripe secret file from " <> cs fileEnv <> ": " <> cs (IOError.ioeGetErrorString err)))
        Nothing ->
            Right . cleanMaybe <$> lookupEnvText valueEnv

lookupEnvText :: String -> IO (Maybe Text)
lookupEnvText name = fmap cs <$> lookupEnv name

cleanMaybe :: Maybe Text -> Maybe Text
cleanMaybe = (>>= \value -> let stripped = Text.strip value in if Text.null stripped then Nothing else Just stripped)

cleanText :: Text -> Maybe Text
cleanText value =
    let stripped = Text.strip value
     in if Text.null stripped then Nothing else Just stripped

buildListPricesRequest :: StripeConfig -> StripeHttpRequest
buildListPricesRequest config =
    let
        lookupKey = fromMaybe defaultPriceLookupKey config.priceLookupKey
        query =
            URI.renderQuery
                True
                [ ("active", Just "true")
                , ("lookup_keys[]", Just (TextEncoding.encodeUtf8 lookupKey))
                , ("expand[]", Just "data.product")
                ]
     in
        StripeHttpRequest
            { stripeRequestMethod = "GET"
            , stripeRequestUrl = defaultStripeRequestBaseUrls.stripeApiBaseUrl <> "/v1/prices" <> TextEncoding.decodeUtf8 query
            , stripeRequestHeaders = stripeAuthHeaders config
            , stripeRequestBody = Nothing
            , stripeRequestTimeoutMicroseconds = stripeHttpTimeoutMicroseconds
            }

buildRetrievePriceRequest :: StripeConfig -> Text -> StripeHttpRequest
buildRetrievePriceRequest config price =
    stripeGetRequest config ("/v1/prices/" <> price)

buildCreateCustomerRequest :: StripeConfig -> Text -> Text -> StripeHttpRequest
buildCreateCustomerRequest config venueId venueName =
    stripePostFormRequest
        config
        (billingIdempotencyKey "customer" venueId Nothing)
        "/v1/customers"
        [ ("name", TextEncoding.encodeUtf8 venueName)
        , ("metadata[venue_id]", TextEncoding.encodeUtf8 venueId)
        , ("metadata[environment]", "bepis")
        ]

buildCreateCheckoutSessionRequest :: StripeConfig -> Text -> Text -> Text -> Text -> Text -> StripeHttpRequest
buildCreateCheckoutSessionRequest config venueId customerId selectedPriceId successUrl cancelUrl =
    stripePostFormRequest
        config
        (billingIdempotencyKey "checkout" venueId (Just selectedPriceId))
        "/v1/checkout/sessions"
        [ ("mode", "subscription")
        , ("customer", TextEncoding.encodeUtf8 customerId)
        , ("line_items[0][price]", TextEncoding.encodeUtf8 selectedPriceId)
        , ("line_items[0][quantity]", "1")
        , ("client_reference_id", TextEncoding.encodeUtf8 venueId)
        , ("metadata[venue_id]", TextEncoding.encodeUtf8 venueId)
        , ("subscription_data[metadata][venue_id]", TextEncoding.encodeUtf8 venueId)
        , ("success_url", TextEncoding.encodeUtf8 successUrl)
        , ("cancel_url", TextEncoding.encodeUtf8 cancelUrl)
        , ("automatic_tax[enabled]", "false")
        , ("tax_id_collection[enabled]", "false")
        ]

buildRetrieveCheckoutSessionRequest :: StripeConfig -> Text -> StripeHttpRequest
buildRetrieveCheckoutSessionRequest config sessionId =
    stripeGetRequest config ("/v1/checkout/sessions/" <> sessionId)

buildCreatePortalSessionRequest :: StripeConfig -> Text -> Text -> Text -> StripeHttpRequest
buildCreatePortalSessionRequest config venueId customerId returnUrl =
    stripePostFormRequest
        config
        (billingIdempotencyKey "portal" venueId Nothing)
        "/v1/billing_portal/sessions"
        [ ("customer", TextEncoding.encodeUtf8 customerId)
        , ("return_url", TextEncoding.encodeUtf8 returnUrl)
        ]

buildRetrieveSubscriptionRequest :: StripeConfig -> Text -> StripeHttpRequest
buildRetrieveSubscriptionRequest config subscriptionId =
    stripeGetRequest config ("/v1/subscriptions/" <> subscriptionId)

stripeGetRequest :: StripeConfig -> Text -> StripeHttpRequest
stripeGetRequest config path =
    StripeHttpRequest
        { stripeRequestMethod = "GET"
        , stripeRequestUrl = defaultStripeRequestBaseUrls.stripeApiBaseUrl <> path
        , stripeRequestHeaders = stripeAuthHeaders config
        , stripeRequestBody = Nothing
        , stripeRequestTimeoutMicroseconds = stripeHttpTimeoutMicroseconds
        }

stripePostFormRequest :: StripeConfig -> Text -> Text -> [(ByteString, ByteString)] -> StripeHttpRequest
stripePostFormRequest config idempotencyKey path formBody =
    StripeHttpRequest
        { stripeRequestMethod = "POST"
        , stripeRequestUrl = defaultStripeRequestBaseUrls.stripeApiBaseUrl <> path
        , stripeRequestHeaders =
            stripeAuthHeaders config
                <> [ ("Idempotency-Key", TextEncoding.encodeUtf8 idempotencyKey)
                   ]
        , stripeRequestBody = Just (StripeFormBody formBody)
        , stripeRequestTimeoutMicroseconds = stripeHttpTimeoutMicroseconds
        }

stripeAuthHeaders :: StripeConfig -> [(HeaderName, ByteString)]
stripeAuthHeaders config =
    [ ("Authorization", "Bearer " <> TextEncoding.encodeUtf8 config.secretKey)
    , ("Stripe-Version", TextEncoding.encodeUtf8 pinnedStripeApiVersion)
    ]

billingIdempotencyKey :: Text -> Text -> Maybe Text -> Text
billingIdempotencyKey operation venueId maybeSuffix =
    Text.take 255 $
        Text.intercalate
            "-"
            ( ["bepis", "billing", normalizeKeyPart operation, normalizeKeyPart venueId]
                <> maybe [] (\suffix -> [normalizeKeyPart suffix]) maybeSuffix
            )

normalizeKeyPart :: Text -> Text
normalizeKeyPart =
    Text.dropAround (== '-')
        . Text.map (\char -> if Char.isAlphaNum char then Char.toLower char else '-')

validateStripeCheckoutRedirectUrl :: Text -> IO (Either Text Text)
validateStripeCheckoutRedirectUrl =
    validateStripeHostedRedirectUrl "Checkout" "checkout.stripe.com"

validateStripePortalRedirectUrl :: Text -> IO (Either Text Text)
validateStripePortalRedirectUrl =
    validateStripeHostedRedirectUrl "Customer Portal" "billing.stripe.com"

validateStripeHostedRedirectUrl :: Text -> ByteString -> Text -> IO (Either Text Text)
validateStripeHostedRedirectUrl surfaceName expectedHost url = do
    Exception.try (parseRequest (cs url)) >>= \case
        Left (_ :: Exception.SomeException) -> pure (Left invalidUrlMessage)
        Right request
            | Http.secure request && Http.port request == 443 && Http.host request == expectedHost -> pure (Right url)
            | otherwise -> pure (Left invalidUrlMessage)
  where
    invalidUrlMessage = "Stripe " <> surfaceName <> " returned an unexpected hosted redirect URL."

validateVenueMonthlyPrice :: StripePrice -> Either Text StripePrice
validateVenueMonthlyPrice price = do
    unless price.active (Left "Stripe Price is not active")
    unless (Text.toLower price.currency == "aud") (Left "Stripe Price currency must be AUD")
    unless (price.unitAmount == Just 10000) (Left "Stripe Price unit amount must be AUD 100.00")
    unless (price.priceType == "recurring") (Left "Stripe Price must be recurring")
    recurringConfig <- maybe (Left "Stripe Price is missing recurring settings") Right price.recurring
    unless (recurringConfig.interval == "month") (Left "Stripe Price interval must be month")
    unless (recurringConfig.intervalCount == 1) (Left "Stripe Price interval count must be 1")
    unless (recurringConfig.usageType == Just "licensed") (Left "Stripe Price usage type must be licensed")
    pure price

sendStripeJsonRequestWith :: Aeson.FromJSON value => (StripeHttpRequest -> IO (Either StripeClientError LByteString.ByteString)) -> Text -> StripeHttpRequest -> IO (Either StripeClientError value)
sendStripeJsonRequestWith transport _label stripeRequest = do
    rawResult <- transport stripeRequest
    pure case rawResult of
        Left err   -> Left err
        Right body -> decodeBodyPure body

sendStripeRawRequest :: StripeHttpRequest -> IO (Either StripeClientError LByteString.ByteString)
sendStripeRawRequest stripeRequest =
    handleStripeHttpExceptions do
        requestWithHeaders <- toHttpRequest stripeRequest
        Timeout.timeout stripeRequest.stripeRequestTimeoutMicroseconds (httpLBS requestWithHeaders) >>= \case
            Nothing -> pure (Left (StripeHttpError "Stripe request timed out"))
            Just response -> decodeStripeRawResponse "Stripe request" response

toHttpRequest :: StripeHttpRequest -> IO Request
toHttpRequest stripeRequest = do
    request <- parseRequest (cs stripeRequest.stripeRequestUrl)
    let requestWithHeaders =
            request
                |> setRequestMethod stripeRequest.stripeRequestMethod
                |> setRequestResponseTimeout (Http.responseTimeoutMicro stripeRequest.stripeRequestTimeoutMicroseconds)
                |> applyRequestHeaders stripeRequest.stripeRequestHeaders
    pure case stripeRequest.stripeRequestBody of
        Nothing -> requestWithHeaders
        Just (StripeFormBody body) -> setRequestBodyURLEncoded body requestWithHeaders

applyRequestHeaders :: [(HeaderName, ByteString)] -> Request -> Request
applyRequestHeaders headers request =
    foldl' (\current (name, value) -> setRequestHeader name [value] current) request headers

handleStripeHttpExceptions :: IO (Either StripeClientError value) -> IO (Either StripeClientError value)
handleStripeHttpExceptions action =
    action `Exception.catch` \(_ :: Exception.SomeException) ->
        pure (Left (StripeHttpError "Stripe request failed before receiving a response"))

decodeStripeRawResponse :: Text -> Response LByteString.ByteString -> IO (Either StripeClientError LByteString.ByteString)
decodeStripeRawResponse label response = do
    let statusCode = getResponseStatusCode response
    let responseBody = getResponseBody response
    if statusCode < 200 || statusCode >= 300
        then pure (Left (StripeHttpError (label <> " failed with status " <> tshow statusCode)))
        else pure (Right responseBody)

decodeBodyPure :: Aeson.FromJSON value => LByteString.ByteString -> Either StripeClientError value
decodeBodyPure body =
    case Aeson.eitherDecode body of
        Left _      -> Left (StripeJsonError "Unable to decode Stripe response")
        Right value -> Right value

data StripeWebhookSignature = StripeWebhookSignature
    { signatureTimestamp :: !Integer
    , matchedSignature   :: !Text
    }
    deriving (Eq, Show)

verifyStripeWebhookSignature :: Text -> Text -> LByteString.ByteString -> IO (Either Text StripeWebhookSignature)
verifyStripeWebhookSignature webhookSecret signatureHeader rawBody = do
    now <- getPOSIXTime
    pure (verifyStripeWebhookSignatureAt now 300 webhookSecret signatureHeader rawBody)

verifyStripeWebhookSignatureAt :: POSIXTime -> Int -> Text -> Text -> LByteString.ByteString -> Either Text StripeWebhookSignature
verifyStripeWebhookSignatureAt now toleranceSeconds webhookSecret signatureHeader rawBody = do
    timestamp <- parseSignatureTimestamp signatureHeader
    signatures <- parseV1Signatures signatureHeader
    let expected = stripeWebhookSignatureHex webhookSecret timestamp rawBody
    unless (any (secureTextEquals expected) signatures) (Left "Stripe webhook signature mismatch")
    let ageSeconds = floor now - timestamp
    when (ageSeconds < 0) (Left "Stripe webhook timestamp is in the future")
    when (ageSeconds > toInteger toleranceSeconds) (Left "Stripe webhook timestamp is outside tolerance")
    pure StripeWebhookSignature { signatureTimestamp = timestamp, matchedSignature = expected }

stripeWebhookSignedPayload :: Integer -> LByteString.ByteString -> ByteString
stripeWebhookSignedPayload timestamp rawBody =
    cs (show timestamp) <> "." <> LByteString.toStrict rawBody

stripeWebhookSignatureHex :: Text -> Integer -> LByteString.ByteString -> Text
stripeWebhookSignatureHex webhookSecret timestamp rawBody =
    let digest = hmac (TextEncoding.encodeUtf8 webhookSecret) (stripeWebhookSignedPayload timestamp rawBody) :: HMAC Hash.SHA256
     in bytesToHex (ByteArray.convert digest)

parseSignatureTimestamp :: Text -> Either Text Integer
parseSignatureTimestamp header =
    case lookup "t" (parseSignatureParts header) >>= readMaybe . cs of
        Just timestamp -> Right timestamp
        Nothing        -> Left "Stripe-Signature is missing a valid timestamp"

parseV1Signatures :: Text -> Either Text [Text]
parseV1Signatures header =
    case map snd (filter ((== "v1") . fst) (parseSignatureParts header)) of
        []         -> Left "Stripe-Signature is missing a v1 signature"
        signatures -> Right signatures

parseSignatureParts :: Text -> [(Text, Text)]
parseSignatureParts header =
    header
        |> Text.splitOn ","
        |> map (Text.breakOn "=")
        |> mapMaybe \case
            (key, valueWithEquals)
                | Text.null valueWithEquals -> Nothing
                | otherwise -> Just (Text.strip key, Text.drop 1 valueWithEquals |> Text.strip)

secureTextEquals :: Text -> Text -> Bool
secureTextEquals expected actual =
    ByteArray.constEq (TextEncoding.encodeUtf8 expected) (TextEncoding.encodeUtf8 actual)

bytesToHex :: ByteString -> Text
bytesToHex =
    Text.concat . map byteToHex . ByteString.unpack
    where
        byteToHex byte =
            let
                high = fromIntegral byte `div` (16 :: Int)
                low = fromIntegral byte `mod` (16 :: Int)
             in
                Text.pack [hexDigit high, hexDigit low]

        hexDigit value
            | value < 10 = Char.chr (Char.ord '0' + value)
            | otherwise = Char.chr (Char.ord 'a' + value - 10)

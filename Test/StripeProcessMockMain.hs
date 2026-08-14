module Test.StripeProcessMockMain (main) where

import Application.Billing.Stripe
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LByteString
import qualified Data.IORef as IORef
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude
import Network.HTTP.Types (status200, status500)
import qualified Network.HTTP.Types.URI as URI
import qualified Network.Wai as Wai
import qualified Network.Wai.Handler.Warp as Warp
import Test.StripeMock (validateStripeRequestHeaders)
import Text.Read (readMaybe)

data MockState = MockState
    { consumedRequests   :: ![Text]
    , failures           :: ![Text]
    , checkoutAttemptIds :: ![Text]
    }

initialState :: MockState
initialState = MockState [] [] []

initialCheckoutSequence :: [Text]
initialCheckoutSequence =
    [ "GET /v1/prices#1"
    , "POST /v1/customers"
    , "POST /v1/checkout/sessions#1"
    , "GET /v1/checkout/sessions/cs_e2e-123"
    ]

retryCheckoutSequence :: [Text]
retryCheckoutSequence =
    initialCheckoutSequence
        <> [ "GET /v1/prices#2"
           , "POST /v1/checkout/sessions#2"
           , "GET /v1/checkout/sessions/cs_e2e-retry-456"
           , "GET /v1/subscriptions/sub_e2e-123"
           ]

main :: IO ()
main = do
    [portText] <- getArgs
    port <- maybe (fail "Stripe process mock requires a numeric port") pure (readMaybe (cs portText :: String))
    stateRef <- IORef.newIORef initialState
    Warp.runSettings
        (Warp.setHost "127.0.0.1" (Warp.setPort port Warp.defaultSettings))
        (stripeProcessMockApp stateRef)

stripeProcessMockApp :: IORef.IORef MockState -> Wai.Application
stripeProcessMockApp stateRef request respond
    | Wai.rawPathInfo request == "/__status" = do
        state <- IORef.readIORef stateRef
        respondJson status200 (Aeson.object
            [ "consumed" Aeson..= reverse state.consumedRequests
            , "failures" Aeson..= reverse state.failures
            , "attemptIds" Aeson..= reverse state.checkoutAttemptIds
            ])
    | otherwise = do
        body <- Wai.strictRequestBody request
        result <- handleStripeRequest stateRef request body
        case result of
            Left failure -> do
                IORef.modifyIORef' stateRef \state -> state { failures = failure : state.failures }
                respondJson status500 (Aeson.object ["error" Aeson..= failure])
            Right responseBody -> respond (Wai.responseLBS status200 [("Content-Type", "application/json")] responseBody)
  where
    respondJson status value = respond (Wai.responseLBS status [("Content-Type", "application/json")] (Aeson.encode value))

handleStripeRequest :: IORef.IORef MockState -> Wai.Request -> LByteString.ByteString -> IO (Either Text LByteString.ByteString)
handleStripeRequest stateRef waiRequest rawBody = do
    state <- IORef.readIORef stateRef
    let path = TextEncoding.decodeUtf8 (Wai.rawPathInfo waiRequest)
    let method = Wai.requestMethod waiRequest
    let request = canonicalRequest waiRequest rawBody
    let consumed = reverse state.consumedRequests
    case (method, path, consumed) of
        ("GET", "/v1/prices", []) ->
            validatePriceLookup stateRef waiRequest request "GET /v1/prices#1"
        ("POST", "/v1/customers", ["GET /v1/prices#1"]) ->
            validateFormAndFinish stateRef request rawBody
                [ ("name", "e2e-alpha-venue")
                , ("email", "e2e-billing-owner@example.com")
                , ("metadata[venue_id]", "a1000000-0000-0000-0000-000000000001")
                , ("metadata[environment]", "bepis")
                ]
                (Just "bepis-billing-customer-a1000000-0000-0000-0000-000000000001")
                "POST /v1/customers"
                Nothing
                =<< customerFixture
        ("POST", "/v1/checkout/sessions", ["GET /v1/prices#1", "POST /v1/customers"]) ->
            validateCheckout stateRef request rawBody "POST /v1/checkout/sessions#1" "cs_e2e-123" "https://checkout.stripe.com/c/pay/cs_test_e2e-sanitized"
        ("GET", "/v1/checkout/sessions/cs_e2e-123", consumedBeforeRetrieve)
            | consumedBeforeRetrieve == take 3 initialCheckoutSequence ->
                finish stateRef request Nothing "GET /v1/checkout/sessions/cs_e2e-123" Nothing =<< checkoutReconciliationFixture "cs_e2e-123" "https://checkout.stripe.com/c/pay/cs_test_e2e-sanitized" "expired" Nothing
        ("GET", "/v1/prices", completedFirstSequence)
            | completedFirstSequence == initialCheckoutSequence ->
                validatePriceLookup stateRef waiRequest request "GET /v1/prices#2"
        ("POST", "/v1/checkout/sessions", consumedBeforeRetry)
            | consumedBeforeRetry == initialCheckoutSequence <> ["GET /v1/prices#2"] ->
                validateCheckout stateRef request rawBody "POST /v1/checkout/sessions#2" "cs_e2e-retry-456" "https://checkout.stripe.com/c/pay/cs_test_e2e-retry-sanitized"
        ("GET", "/v1/checkout/sessions/cs_e2e-retry-456", consumedBeforeRetryRetrieve)
            | consumedBeforeRetryRetrieve == take 6 retryCheckoutSequence ->
                finish stateRef request Nothing "GET /v1/checkout/sessions/cs_e2e-retry-456" Nothing =<< checkoutReconciliationFixture "cs_e2e-retry-456" "https://checkout.stripe.com/c/pay/cs_test_e2e-retry-sanitized" "complete" (Just "sub_e2e-123")
        ("GET", "/v1/subscriptions/sub_e2e-123", consumedBeforeSubscriptionRetrieve)
            | consumedBeforeSubscriptionRetrieve == take 7 retryCheckoutSequence ->
                finish stateRef request Nothing "GET /v1/subscriptions/sub_e2e-123" Nothing =<< reconciliationSubscriptionFixture
        ("POST", "/v1/billing_portal/sessions", completedSecondSequence)
            | completedSecondSequence == retryCheckoutSequence ->
                validatePortal stateRef request rawBody
        _ -> pure (Left ("Unexpected or reordered Stripe request: " <> cs method <> " " <> path))

validatePriceLookup :: IORef.IORef MockState -> Wai.Request -> StripeHttpRequest -> Text -> IO (Either Text LByteString.ByteString)
validatePriceLookup stateRef waiRequest request label = do
    let expectedQuery = List.sort [("active", Just "true"), ("lookup_keys[]", Just "bepis_venue_monthly_aud_100"), ("expand[]", Just "data.product")]
    if List.sort (Wai.queryString waiRequest) /= expectedQuery
        then pure (Left "Price lookup query did not match the canonical strict contract")
        else finish stateRef request Nothing label Nothing =<< fixture "prices.json"

validateCheckout :: IORef.IORef MockState -> StripeHttpRequest -> LByteString.ByteString -> Text -> Text -> Text -> IO (Either Text LByteString.ByteString)
validateCheckout stateRef request rawBody label sessionId hostedUrl = do
    let form = decodedForm rawBody
    let maybeKey = lookup "Idempotency-Key" request.stripeRequestHeaders
    case maybeKey >>= ByteString.stripPrefix "bepis-billing-checkout-" of
        Nothing -> pure (Left "Checkout idempotency key was missing its committed-attempt scope")
        Just rawAttemptId -> do
            let attemptId = TextEncoding.decodeUtf8 rawAttemptId
            let successUrl = fromMaybe "" (lookup "success_url" form)
            let cancelUrl = fromMaybe "" (lookup "cancel_url" form)
            let expected =
                    [ ("mode", "subscription")
                    , ("customer", "cus_e2e-123")
                    , ("line_items[0][price]", "price_valid")
                    , ("line_items[0][quantity]", "1")
                    , ("client_reference_id", "a1000000-0000-0000-0000-000000000001")
                    , ("metadata[venue_id]", "a1000000-0000-0000-0000-000000000001")
                    , ("subscription_data[metadata][venue_id]", "a1000000-0000-0000-0000-000000000001")
                    , ("success_url", successUrl)
                    , ("cancel_url", cancelUrl)
                    , ("automatic_tax[enabled]", "false")
                    , ("tax_id_collection[enabled]", "false")
                    ]
            response <- checkoutFixture sessionId hostedUrl
            if not (Text.isInfixOf ("attempt_id=" <> attemptId) (TextEncoding.decodeUtf8 successUrl))
                || not (Text.isInfixOf ("attempt_id=" <> attemptId) (TextEncoding.decodeUtf8 cancelUrl))
                then pure (Left "Checkout return URLs did not correlate to the idempotent local attempt")
                else validateFormAndFinish stateRef request rawBody expected maybeKey label (Just attemptId) response

validatePortal :: IORef.IORef MockState -> StripeHttpRequest -> LByteString.ByteString -> IO (Either Text LByteString.ByteString)
validatePortal stateRef request rawBody = do
    let form = decodedForm rawBody
    let returnUrl = fromMaybe "" (lookup "return_url" form)
    let maybePortalKey = lookup "Idempotency-Key" request.stripeRequestHeaders
    portal <- fixtureValue "portal-session.json"
    let response =
            setJsonText "customer" "cus_e2e-123" $
                setJsonText "return_url" (TextEncoding.decodeUtf8 returnUrl) portal
    case maybePortalKey >>= ByteString.stripPrefix "bepis-billing-portal-a1000000-0000-0000-0000-000000000001-" of
        Nothing -> pure (Left "Portal idempotency key was missing its fresh request scope")
        Just suffix | ByteString.null suffix -> pure (Left "Portal idempotency key had an empty request scope")
        Just _ ->
            validateFormAndFinish stateRef request rawBody
                [("customer", "cus_e2e-123"), ("return_url", returnUrl)]
                maybePortalKey
                "POST /v1/billing_portal/sessions"
                Nothing
                (Aeson.encode response)

decodedForm :: LByteString.ByteString -> [(ByteString, ByteString)]
decodedForm rawBody = [(name, value) | (name, Just value) <- URI.parseQuery (LByteString.toStrict rawBody)]

validateFormAndFinish stateRef request rawBody expected expectedKey label attemptId responseBody =
    if List.sort (decodedForm rawBody) /= List.sort expected
        then pure (Left (label <> " form fields did not match the canonical strict contract"))
        else finish stateRef request expectedKey label attemptId responseBody

finish stateRef request expectedKey label attemptId responseBody =
    case validateProcessRequest request expectedKey of
        Left failure -> pure (Left failure)
        Right () -> do
            IORef.modifyIORef' stateRef \state ->
                state
                    { consumedRequests = label : state.consumedRequests
                    , checkoutAttemptIds = maybe state.checkoutAttemptIds (: state.checkoutAttemptIds) attemptId
                    }
            pure (Right responseBody)

validateProcessRequest :: StripeHttpRequest -> Maybe ByteString -> Either Text ()
validateProcessRequest request expectedKey = do
    validateStripeRequestHeaders expectedKey request
    when (request.stripeRequestMethod == "POST") do
        let contentType = fromMaybe "" (lookup "Content-Type" request.stripeRequestHeaders)
        unless ("application/x-www-form-urlencoded" `ByteString.isPrefixOf` contentType) do
            Left "Stripe POST request was missing form content type"

canonicalRequest :: Wai.Request -> LByteString.ByteString -> StripeHttpRequest
canonicalRequest request rawBody =
    StripeHttpRequest
        { stripeRequestMethod = Wai.requestMethod request
        , stripeRequestUrl = "https://api.stripe.com" <> TextEncoding.decodeUtf8 (Wai.rawPathInfo request <> Wai.rawQueryString request)
        , stripeRequestHeaders = Wai.requestHeaders request
        , stripeRequestBody = if LByteString.null rawBody then Nothing else Just (StripeFormBody (decodedForm rawBody))
        , stripeRequestTimeoutMicroseconds = 15000000
        }

customerFixture :: IO LByteString.ByteString
customerFixture =
    Aeson.encode . setJsonText "id" "cus_e2e-123" <$> fixtureValue "customer.json"

checkoutFixture :: Text -> Text -> IO LByteString.ByteString
checkoutFixture sessionId hostedUrl = do
    value <- fixtureValue "checkout-session-created.json"
    pure $
        Aeson.encode $
            setJsonText "customer" "cus_e2e-123" $
                setJsonText "url" hostedUrl $
                    setJsonText "id" sessionId value

checkoutReconciliationFixture :: Text -> Text -> Text -> Maybe Text -> IO LByteString.ByteString
checkoutReconciliationFixture sessionId hostedUrl status maybeSubscriptionId = do
    fixtureValue' <- fixtureValue "checkout-session-created.json"
    let value = replaceFixtureText "venue-123" "a1000000-0000-0000-0000-000000000001" fixtureValue'
    pure $
        Aeson.encode $
            setJsonValue "subscription" (maybe Aeson.Null Aeson.String maybeSubscriptionId) $
                setJsonText "status" status $
                    setJsonText "customer" "cus_e2e-123" $
                        setJsonText "url" hostedUrl $
                            setJsonText "id" sessionId value

reconciliationSubscriptionFixture :: IO LByteString.ByteString
reconciliationSubscriptionFixture = do
    value <- fixtureValue "subscription.json"
    pure $ Aeson.encode $ setJsonValue "cancel_at_period_end" (Aeson.Bool False) $ replaceFixtureText "venue-123" "a1000000-0000-0000-0000-000000000001" $ replaceFixtureText "cus_123" "cus_e2e-123" $ replaceFixtureText "sub_123" "sub_e2e-123" value

fixture :: FilePath -> IO LByteString.ByteString
fixture name = LByteString.readFile ("Test/Fixtures/stripe/2026-06-24.dahlia/" <> name)

fixtureValue :: FilePath -> IO Aeson.Value
fixtureValue name = do
    body <- fixture name
    maybe (fail ("Invalid fixture " <> name)) pure (Aeson.decode body)

setJsonText :: Aeson.Key -> Text -> Aeson.Value -> Aeson.Value
setJsonText key value = setJsonValue key (Aeson.String value)

setJsonValue :: Aeson.Key -> Aeson.Value -> Aeson.Value -> Aeson.Value
setJsonValue key value (Aeson.Object object) = Aeson.Object (KeyMap.insert key value object)
setJsonValue _ _ value = value

replaceFixtureText :: Text -> Text -> Aeson.Value -> Aeson.Value
replaceFixtureText old new = \case
    Aeson.String value | value == old -> Aeson.String new
    Aeson.Object object -> Aeson.Object (fmap (replaceFixtureText old new) object)
    Aeson.Array values -> Aeson.Array (fmap (replaceFixtureText old new) values)
    value -> value

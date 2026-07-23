module Test.StripeContractSpec where

import Application.Billing.Stripe
import qualified Data.ByteString.Lazy as LByteString
import Data.Text (Text)
import IHP.Prelude
import Test.Hspec
import Test.StripeMock

tests :: Spec
tests =
    describe "StripeContract" do
        it "runs the launch Checkout and Portal API sequence against a strict local mock" do
            fixtures <- readLaunchFixtures
            mock <- newStrictStripeMock (launchExpectations fixtures)
            let client = stripeClientWithTransport (strictStripeTransport mock)

            prices <- listPrices client testConfig
            prices `shouldBe` Right [validPrice]
            fmap (map validateVenueMonthlyPrice) prices `shouldBe` Right [Right validPrice]

            retrievedPrice <- retrievePrice client testConfig "price_valid"
            retrievedPrice `shouldBe` Right validPrice
            fmap validateVenueMonthlyPrice retrievedPrice `shouldBe` Right (Right validPrice)

            customer <- createCustomer client testConfig "venue-123" "Venue Name" "owner@example.test"
            customer
                `shouldBe` Right StripeCustomer
                    { stripeCustomerId = "cus_123"
                    , stripeCustomerLivemode = False
                    }

            checkout <-
                createCheckoutSession
                    client
                    testConfig
                    "attempt-456"
                    "venue-123"
                    "cus_123"
                    "price_valid"
                    "https://app.example.test/BillingSuccess?attempt_id=attempt-456&session_id={CHECKOUT_SESSION_ID}"
                    "https://app.example.test/BillingCancel?attempt_id=attempt-456"
            let createdCheckoutUrl = "https://checkout.stripe.com/c/pay/cs_test_sanitized"
            let createdCheckoutSession =
                    StripeCheckoutSession
                        { stripeCheckoutSessionId = "cs_123"
                        , stripeCheckoutSessionUrl = Just createdCheckoutUrl
                        , stripeCheckoutCustomerId = Just "cus_123"
                        , stripeCheckoutSubscriptionId = Nothing
                        , stripeCheckoutClientReferenceId = Just "venue-123"
                        , stripeCheckoutVenueId = Just "venue-123"
                        , stripeCheckoutLivemode = False
                        , stripeCheckoutMode = "subscription"
                        , stripeCheckoutStatus = "open"
                        , stripeCheckoutExpiresAt = 1784764800
                        }
            checkout `shouldBe` Right createdCheckoutSession
            validateCreatedCheckoutSession "cus_123" createdCheckoutSession `shouldBe` Right createdCheckoutSession
            validateStripeCheckoutRedirectUrl createdCheckoutUrl `shouldReturn` Right createdCheckoutUrl

            fetchedCheckout <- retrieveCheckoutSession client testConfig "cs_123" "cus_123"
            fetchedCheckout
                `shouldBe` Right
                    createdCheckoutSession
                        { stripeCheckoutSubscriptionId = Just "sub_123"
                        , stripeCheckoutStatus = "complete"
                        }

            portal <- createPortalSession client testConfig "request-789" "venue-123" "cus_123" "https://app.example.test/Billing"
            portal
                `shouldBe` Right
                    StripePortalSession
                        { stripePortalSessionId = "bps_123"
                        , stripePortalSessionUrl = "https://billing.stripe.com/p/session/bps_test_sanitized"
                        , stripePortalSessionLivemode = False
                        , stripePortalCustomerId = "cus_123"
                        , stripePortalReturnUrl = "https://app.example.test/Billing"
                        }
            case portal of
                Right portalSession ->
                    validateStripePortalRedirectUrl portalSession.stripePortalSessionUrl
                        `shouldReturn` Right portalSession.stripePortalSessionUrl
                Left _ -> expectationFailure "expected the Portal fixture to decode"

            subscription <- retrieveSubscription client testConfig "sub_123"
            subscription
                `shouldBe` Right
                    StripeSubscription
                        { stripeSubscriptionId = "sub_123"
                        , stripeSubscriptionCustomerId = "cus_123"
                        , stripeSubscriptionVenueId = Just "venue-123"
                        , stripeSubscriptionLivemode = False
                        , stripeSubscriptionStatus = "active"
                        , stripeSubscriptionPriceId = "price_valid"
                        , stripeSubscriptionPriceLivemode = False
                        , stripeSubscriptionCurrentPeriodStart = 1784678400
                        , stripeSubscriptionCurrentPeriodEnd = 1787356800
                        , stripeSubscriptionCancelAtPeriodEnd = True
                        }

            assertStripeMockConsumed mock

        it "rejects responses whose Stripe object discriminator is wrong" do
            let wrongPrice = "{\"id\":\"price_wrong_object\",\"object\":\"customer\",\"active\":true,\"currency\":\"aud\",\"livemode\":false,\"unit_amount\":10000,\"type\":\"recurring\",\"recurring\":{\"interval\":\"month\",\"interval_count\":1,\"usage_type\":\"licensed\"}}"
            let wrongCustomer = "{\"id\":\"cus_wrong_object\",\"object\":\"price\",\"livemode\":false}"
            let wrongCheckout = "{\"id\":\"cs_wrong_object\",\"object\":\"customer\",\"url\":null,\"customer\":null,\"subscription\":null,\"livemode\":false,\"mode\":\"subscription\",\"status\":\"open\"}"
            let wrongPortal = "{\"id\":\"bps_wrong_object\",\"object\":\"customer\",\"url\":\"https://billing.stripe.com/p/session/sanitized\",\"livemode\":false}"

            price <- retrievePrice (fixtureClient wrongPrice) testConfig "price_wrong_object"
            customer <- createCustomer (fixtureClient wrongCustomer) testConfig "venue-123" "Venue Name" "owner@example.test"
            checkout <- createCheckoutSession (fixtureClient wrongCheckout) testConfig "attempt-456" "venue-123" "cus_123" "price_valid" "https://app.example.test/success" "https://app.example.test/cancel"
            portal <- createPortalSession (fixtureClient wrongPortal) testConfig "request-789" "venue-123" "cus_123" "https://app.example.test/Billing"

            price `shouldBe` Left (StripeJsonError "Unable to decode Stripe response")
            customer `shouldBe` Left (StripeJsonError "Unable to decode Stripe response")
            checkout `shouldBe` Left (StripeJsonError "Unable to decode Stripe response")
            portal `shouldBe` Left (StripeJsonError "Unable to decode Stripe response")

        it "rejects live Stripe objects returned to test mode" do
            let livePriceResponse =
                    "{\"object\":\"list\",\"data\":[{\"id\":\"price_live\",\"object\":\"price\",\"active\":true,\"currency\":\"aud\",\"livemode\":true,\"unit_amount\":10000,\"type\":\"recurring\",\"recurring\":{\"interval\":\"month\",\"interval_count\":1,\"usage_type\":\"licensed\"}}]}"
            let client = stripeClientWithTransport (const (pure (Right livePriceResponse)))

            result <- listPrices client testConfig

            result
                `shouldBe` Left
                    (StripeJsonError "Stripe price lookup returned live-mode data to a test-mode integration")

        it "rejects test-mode Customer, Checkout, Portal, and Subscription data in live mode" do
            fixtures <- readLaunchFixtures
            let liveConfig = testConfig { stripeMode = StripeLiveMode }

            customer <- createCustomer (fixtureClient fixtures.customerFixture) liveConfig "venue-123" "Venue Name" "owner@example.test"
            checkout <- createCheckoutSession (fixtureClient fixtures.checkoutCreatedFixture) liveConfig "attempt-456" "venue-123" "cus_123" "price_valid" "https://app.example.test/success" "https://app.example.test/cancel"
            portal <- createPortalSession (fixtureClient fixtures.portalFixture) liveConfig "request-789" "venue-123" "cus_123" "https://app.example.test/Billing"
            subscription <- retrieveSubscription (fixtureClient fixtures.subscriptionFixture) liveConfig "sub_123"

            customer `responseShouldFailMode` "Stripe customer create returned test-mode data to a live-mode integration"
            checkout `responseShouldFailMode` "Stripe checkout session create returned test-mode data to a live-mode integration"
            portal `responseShouldFailMode` "Stripe portal session create returned test-mode data to a live-mode integration"
            subscription `responseShouldFailMode` "Stripe subscription retrieve returned test-mode data to a live-mode integration"

        it "rejects a Subscription Item Price from the opposite Stripe mode" do
            response <- LByteString.readFile "Test/Fixtures/stripe/2026-06-24.dahlia/subscription-price-mode-mismatch.json"

            result <- retrieveSubscription (fixtureClient response) testConfig "sub_price_mode_mismatch"

            result
                `shouldBe` Left
                    (StripeJsonError "Stripe subscription item price returned live-mode data to a test-mode integration")

        it "rejects Subscription retrieval when Stripe returns multiple plan items" do
            response <- LByteString.readFile "Test/Fixtures/stripe/2026-06-24.dahlia/subscription-multiple-items.json"
            let client = stripeClientWithTransport (const (pure (Right response)))

            result <- retrieveSubscription client testConfig "sub_multiple"

            result `shouldBe` Left (StripeJsonError "Unable to decode Stripe response")

        it "fails closed on unexpected request shape" do
            fixtures <- readLaunchFixtures
            mock <-
                newStrictStripeMock
                    [ listPricesExpectation fixtures.pricesFixture "wrong_lookup"
                    ]
            let client = stripeClientWithTransport (strictStripeTransport mock)

            result <- listPrices client testConfig

            result `shouldBe` Left (StripeHttpError "Unexpected Stripe query for /v1/prices")

testConfig :: StripeConfig
testConfig =
    StripeConfig
        { secretKey = "sk_test_123"
        , webhookSecret = "whsec_test_123"
        , priceLookupKey = Just defaultPriceLookupKey
        , priceId = Nothing
        , appBaseUrl = "https://app.example.test"
        , stripeMode = StripeTestMode
        , stripeDeploymentControls =
            StripeDeploymentControls
                { stripeBillingEnabled = True
                , stripeCheckoutEnabled = True
                , stripeOwnerNavigationVisible = False
                }
        }

validRecurring :: StripeRecurring
validRecurring =
    StripeRecurring
        { interval = "month"
        , intervalCount = 1
        , usageType = Just "licensed"
        }

validPrice :: StripePrice
validPrice =
    StripePrice
        { stripePriceId = "price_valid"
        , stripePriceLivemode = False
        , active = True
        , currency = "aud"
        , unitAmount = Just 10000
        , priceType = "recurring"
        , recurring = Just validRecurring
        }

fixtureClient :: LByteString.ByteString -> StripeClient
fixtureClient fixture =
    stripeClientWithTransport (const (pure (Right fixture)))

responseShouldFailMode :: Either StripeClientError value -> Text -> Expectation
responseShouldFailMode result expectedMessage =
    case result of
        Left (StripeJsonError message) -> message `shouldBe` expectedMessage
        _ -> expectationFailure "expected Stripe response mode validation to fail"

data LaunchFixtures = LaunchFixtures
    { pricesFixture          :: !LByteString.ByteString
    , priceFixture           :: !LByteString.ByteString
    , customerFixture        :: !LByteString.ByteString
    , checkoutCreatedFixture :: !LByteString.ByteString
    , checkoutFixture        :: !LByteString.ByteString
    , portalFixture          :: !LByteString.ByteString
    , subscriptionFixture    :: !LByteString.ByteString
    }

readLaunchFixtures :: IO LaunchFixtures
readLaunchFixtures =
    LaunchFixtures
        <$> readFixture "prices.json"
        <*> readFixture "price.json"
        <*> readFixture "customer.json"
        <*> readFixture "checkout-session-created.json"
        <*> readFixture "checkout-session.json"
        <*> readFixture "portal-session.json"
        <*> readFixture "subscription.json"
  where
    readFixture name = LByteString.readFile ("Test/Fixtures/stripe/2026-06-24.dahlia/" <> name)

launchExpectations :: LaunchFixtures -> [ExpectedStripeRequest]
launchExpectations fixtures =
    [ listPricesExpectation fixtures.pricesFixture defaultPriceLookupKey
    , ExpectedStripeRequest
        { expectedMethod = "GET"
        , expectedPath = "/v1/prices/price_valid"
        , expectedQuery = []
        , expectedFormBody = []
        , expectedIdempotencyKey = Nothing
        , responseBody = fixtures.priceFixture
        }
    , ExpectedStripeRequest
        { expectedMethod = "POST"
        , expectedPath = "/v1/customers"
        , expectedQuery = []
        , expectedFormBody =
            [ ("name", "Venue Name")
            , ("email", "owner@example.test")
            , ("metadata[venue_id]", "venue-123")
            , ("metadata[environment]", "bepis")
            ]
        , expectedIdempotencyKey = Just "bepis-billing-customer-venue-123"
        , responseBody = fixtures.customerFixture
        }
    , ExpectedStripeRequest
        { expectedMethod = "POST"
        , expectedPath = "/v1/checkout/sessions"
        , expectedQuery = []
        , expectedFormBody =
            [ ("mode", "subscription")
            , ("customer", "cus_123")
            , ("line_items[0][price]", "price_valid")
            , ("line_items[0][quantity]", "1")
            , ("client_reference_id", "venue-123")
            , ("metadata[venue_id]", "venue-123")
            , ("subscription_data[metadata][venue_id]", "venue-123")
            , ("success_url", "https://app.example.test/BillingSuccess?attempt_id=attempt-456&session_id={CHECKOUT_SESSION_ID}")
            , ("cancel_url", "https://app.example.test/BillingCancel?attempt_id=attempt-456")
            , ("automatic_tax[enabled]", "false")
            , ("tax_id_collection[enabled]", "false")
            ]
        , expectedIdempotencyKey = Just "bepis-billing-checkout-attempt-456"
        , responseBody = fixtures.checkoutCreatedFixture
        }
    , ExpectedStripeRequest
        { expectedMethod = "GET"
        , expectedPath = "/v1/checkout/sessions/cs_123"
        , expectedQuery = []
        , expectedFormBody = []
        , expectedIdempotencyKey = Nothing
        , responseBody = fixtures.checkoutFixture
        }
    , ExpectedStripeRequest
        { expectedMethod = "POST"
        , expectedPath = "/v1/billing_portal/sessions"
        , expectedQuery = []
        , expectedFormBody =
            [ ("customer", "cus_123")
            , ("return_url", "https://app.example.test/Billing")
            ]
        , expectedIdempotencyKey = Just "bepis-billing-portal-venue-123-request-789"
        , responseBody = fixtures.portalFixture
        }
    , ExpectedStripeRequest
        { expectedMethod = "GET"
        , expectedPath = "/v1/subscriptions/sub_123"
        , expectedQuery = []
        , expectedFormBody = []
        , expectedIdempotencyKey = Nothing
        , responseBody = fixtures.subscriptionFixture
        }
    ]

listPricesExpectation :: LByteString.ByteString -> Text -> ExpectedStripeRequest
listPricesExpectation response lookupKey =
    ExpectedStripeRequest
        { expectedMethod = "GET"
        , expectedPath = "/v1/prices"
        , expectedQuery =
            [ ("active", Just "true")
            , ("lookup_keys[]", Just (cs lookupKey))
            , ("expand[]", Just "data.product")
            ]
        , expectedFormBody = []
        , expectedIdempotencyKey = Nothing
        , responseBody = response
        }

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

            customer <- createCustomer client testConfig "venue-123" "Venue Name"
            customer
                `shouldBe` Right StripeCustomer
                    { stripeCustomerId = "cus_123"
                    , stripeCustomerLivemode = False
                    }

            checkout <-
                createCheckoutSession
                    client
                    testConfig
                    "venue-123"
                    "cus_123"
                    "price_valid"
                    "https://app.example.test/BillingSuccess?session_id={CHECKOUT_SESSION_ID}"
                    "https://app.example.test/BillingCancel"
            checkout
                `shouldBe` Right
                    StripeCheckoutSession
                        { stripeCheckoutSessionId = "cs_123"
                        , stripeCheckoutSessionUrl = Just "https://checkout.stripe.test/session"
                        , stripeCheckoutCustomerId = Just "cus_123"
                        , stripeCheckoutSubscriptionId = Just "sub_123"
                        , stripeCheckoutLivemode = False
                        , stripeCheckoutMode = "subscription"
                        , stripeCheckoutStatus = "complete"
                        }

            fetchedCheckout <- retrieveCheckoutSession client testConfig "cs_123"
            fetchedCheckout `shouldBe` checkout

            portal <- createPortalSession client testConfig "venue-123" "cus_123" "https://app.example.test/Billing"
            portal
                `shouldBe` Right
                    StripePortalSession
                        { stripePortalSessionId = "bps_123"
                        , stripePortalSessionUrl = "https://billing.stripe.test/session"
                        , stripePortalSessionLivemode = False
                        }

            subscription <- retrieveSubscription client testConfig "sub_123"
            subscription
                `shouldBe` Right
                    StripeSubscription
                        { stripeSubscriptionId = "sub_123"
                        , stripeSubscriptionCustomerId = "cus_123"
                        , stripeSubscriptionLivemode = False
                        , stripeSubscriptionStatus = "active"
                        , stripeSubscriptionPriceId = "price_valid"
                        , stripeSubscriptionCurrentPeriodStart = 1784678400
                        , stripeSubscriptionCurrentPeriodEnd = 1787356800
                        , stripeSubscriptionCancelAtPeriodEnd = True
                        }

            assertStripeMockConsumed mock

        it "rejects Subscription retrieval when Stripe returns multiple plan items" do
            response <- LByteString.readFile "Test/Fixtures/stripe/2026-06-24.dahlia/subscription-multiple-items.json"
            let client = stripeClientWithTransport (const (pure (Right response)))

            result <- retrieveSubscription client testConfig "sub_multiple"

            result `shouldSatisfy` \case
                Left (StripeJsonError message) -> "must not contain multiple items" `isInfixOf` message
                _ -> False

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

data LaunchFixtures = LaunchFixtures
    { pricesFixture       :: !LByteString.ByteString
    , customerFixture     :: !LByteString.ByteString
    , checkoutFixture     :: !LByteString.ByteString
    , portalFixture       :: !LByteString.ByteString
    , subscriptionFixture :: !LByteString.ByteString
    }

readLaunchFixtures :: IO LaunchFixtures
readLaunchFixtures =
    LaunchFixtures
        <$> readFixture "prices.json"
        <*> readFixture "customer.json"
        <*> readFixture "checkout-session.json"
        <*> readFixture "portal-session.json"
        <*> readFixture "subscription.json"
  where
    readFixture name = LByteString.readFile ("Test/Fixtures/stripe/2026-06-24.dahlia/" <> name)

launchExpectations :: LaunchFixtures -> [ExpectedStripeRequest]
launchExpectations fixtures =
    [ listPricesExpectation fixtures.pricesFixture defaultPriceLookupKey
    , ExpectedStripeRequest
        { expectedMethod = "POST"
        , expectedPath = "/v1/customers"
        , expectedQuery = []
        , expectedFormBody =
            [ ("name", "Venue Name")
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
            , ("success_url", "https://app.example.test/BillingSuccess?session_id={CHECKOUT_SESSION_ID}")
            , ("cancel_url", "https://app.example.test/BillingCancel")
            , ("automatic_tax[enabled]", "false")
            , ("tax_id_collection[enabled]", "false")
            ]
        , expectedIdempotencyKey = Just "bepis-billing-checkout-venue-123-price-valid"
        , responseBody = fixtures.checkoutFixture
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
        , expectedIdempotencyKey = Just "bepis-billing-portal-venue-123"
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

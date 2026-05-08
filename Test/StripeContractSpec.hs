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
            mock <- newStrictStripeMock launchExpectations
            let client = stripeClientWithTransport (strictStripeTransport mock)

            prices <- listPrices client testConfig
            prices `shouldBe` Right [validPrice]
            fmap (map validateVenueMonthlyPrice) prices `shouldBe` Right [Right validPrice]

            customer <- createCustomer client testConfig "venue-123" "Venue Name"
            customer `shouldBe` Right StripeCustomer { stripeCustomerId = "cus_123" }

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
                        }

            fetchedCheckout <- retrieveCheckoutSession client testConfig "cs_123"
            fetchedCheckout `shouldBe` checkout

            portal <- createPortalSession client testConfig "venue-123" "cus_123" "https://app.example.test/Billing"
            portal
                `shouldBe` Right
                    StripePortalSession
                        { stripePortalSessionId = "bps_123"
                        , stripePortalSessionUrl = "https://billing.stripe.test/session"
                        }

            subscription <- retrieveSubscription client testConfig "sub_123"
            subscription
                `shouldBe` Right
                    StripeSubscription
                        { stripeSubscriptionId = "sub_123"
                        , stripeSubscriptionStatus = "active"
                        }

            assertStripeMockConsumed mock

        it "fails closed on unexpected request shape" do
            mock <-
                newStrictStripeMock
                    [ (listPricesExpectation "wrong_lookup")
                        { responseBody = priceListResponse
                        }
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
        , active = True
        , currency = "aud"
        , unitAmount = Just 10000
        , priceType = "recurring"
        , recurring = Just validRecurring
        }

launchExpectations :: [ExpectedStripeRequest]
launchExpectations =
    [ listPricesExpectation defaultPriceLookupKey
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
        , responseBody = "{\"id\":\"cus_123\",\"object\":\"customer\"}"
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
        , responseBody = "{\"id\":\"cs_123\",\"object\":\"checkout.session\",\"url\":\"https://checkout.stripe.test/session\",\"customer\":\"cus_123\",\"subscription\":\"sub_123\"}"
        }
    , ExpectedStripeRequest
        { expectedMethod = "GET"
        , expectedPath = "/v1/checkout/sessions/cs_123"
        , expectedQuery = []
        , expectedFormBody = []
        , expectedIdempotencyKey = Nothing
        , responseBody = "{\"id\":\"cs_123\",\"object\":\"checkout.session\",\"url\":\"https://checkout.stripe.test/session\",\"customer\":\"cus_123\",\"subscription\":\"sub_123\"}"
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
        , responseBody = "{\"id\":\"bps_123\",\"object\":\"billing_portal.session\",\"url\":\"https://billing.stripe.test/session\"}"
        }
    , ExpectedStripeRequest
        { expectedMethod = "GET"
        , expectedPath = "/v1/subscriptions/sub_123"
        , expectedQuery = []
        , expectedFormBody = []
        , expectedIdempotencyKey = Nothing
        , responseBody = "{\"id\":\"sub_123\",\"object\":\"subscription\",\"status\":\"active\"}"
        }
    ]

listPricesExpectation :: Text -> ExpectedStripeRequest
listPricesExpectation lookupKey =
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
        , responseBody = priceListResponse
        }

priceListResponse :: LByteString.ByteString
priceListResponse =
    "{\"object\":\"list\",\"data\":[{\"id\":\"price_valid\",\"object\":\"price\",\"active\":true,\"currency\":\"aud\",\"unit_amount\":10000,\"type\":\"recurring\",\"recurring\":{\"interval\":\"month\",\"interval_count\":1,\"usage_type\":\"licensed\"}}]}"

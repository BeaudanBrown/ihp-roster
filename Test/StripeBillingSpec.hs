module Test.StripeBillingSpec where

import Application.Billing.Stripe
import Control.Exception (bracket, bracket_)
import qualified Data.Bifunctor as Bifunctor
import qualified Data.ByteString.Lazy as LByteString
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import IHP.Prelude
import Network.HTTP.Types.Status (status302)
import qualified Network.Wai as Wai
import qualified Network.Wai.Handler.Warp as Warp
import qualified System.Directory as Directory
import qualified System.Environment as Environment
import System.IO (hClose, openTempFile)
import Test.Hspec

tests :: Spec
tests =
    describe "StripeBilling" do
        describe "configuration" do
            it "loads file-backed secrets and the default price lookup key" do
                withTempSecret "sk_test_file" \secretPath ->
                    withTempSecret "whsec_file" \webhookPath ->
                        withStripeEnv
                            [ ("STRIPE_SECRET_KEY_FILE", Just secretPath)
                            , ("STRIPE_WEBHOOK_SECRET_FILE", Just webhookPath)
                            , ("STRIPE_SECRET_KEY", Nothing)
                            , ("STRIPE_WEBHOOK_SECRET", Nothing)
                            , ("STRIPE_PRICE_LOOKUP_KEY", Nothing)
                            , ("STRIPE_PRICE_ID", Nothing)
                            , ("STRIPE_MODE", Just "test")
                            , ("STRIPE_BILLING_ENABLED", Just "true")
                            , ("STRIPE_CHECKOUT_ENABLED", Just "false")
                            , ("STRIPE_OWNER_NAVIGATION_VISIBLE", Just "false")
                            , ("APP_BASE_URL", Just "https://app.example.test")
                            ]
                            do
                                result <- readStripeConfig

                                fmap (.secretKey) result `shouldBe` Right "sk_test_file"
                                fmap (.webhookSecret) result `shouldBe` Right "whsec_file"
                                fmap (.priceLookupKey) result `shouldBe` Right (Just defaultPriceLookupKey)
                                fmap (.priceId) result `shouldBe` Right Nothing
                                fmap (.appBaseUrl) result `shouldBe` Right "https://app.example.test"
                                fmap (.stripeMode) result `shouldBe` Right StripeTestMode
                                fmap (.stripeDeploymentControls) result
                                    `shouldBe` Right
                                        StripeDeploymentControls
                                            { stripeBillingEnabled = True
                                            , stripeCheckoutEnabled = False
                                            , stripeOwnerNavigationVisible = False
                                            }

            it "allows direct price id fallback without inventing a lookup key" do
                withStripeEnv
                    [ ("STRIPE_SECRET_KEY_FILE", Nothing)
                    , ("STRIPE_WEBHOOK_SECRET_FILE", Nothing)
                    , ("STRIPE_SECRET_KEY", Just "sk_test_env")
                    , ("STRIPE_WEBHOOK_SECRET", Just "whsec_env")
                    , ("STRIPE_PRICE_LOOKUP_KEY", Nothing)
                    , ("STRIPE_PRICE_ID", Just "price_direct")
                    , ("STRIPE_MODE", Just "test")
                    , ("STRIPE_BILLING_ENABLED", Just "true")
                    , ("STRIPE_CHECKOUT_ENABLED", Just "true")
                    , ("STRIPE_OWNER_NAVIGATION_VISIBLE", Just "false")
                    ]
                    do
                        result <- readStripeConfig

                        fmap (.priceLookupKey) result `shouldBe` Right Nothing
                        fmap (.priceId) result `shouldBe` Right (Just "price_direct")

            it "rejects simultaneous Price lookup key and direct Price ID" do
                withStripeEnv
                    [ ("STRIPE_SECRET_KEY_FILE", Nothing)
                    , ("STRIPE_WEBHOOK_SECRET_FILE", Nothing)
                    , ("STRIPE_SECRET_KEY", Just "sk_test_not_a_real_key")
                    , ("STRIPE_WEBHOOK_SECRET", Just "whsec_not_a_real_secret")
                    , ("STRIPE_PRICE_LOOKUP_KEY", Just "bepis_venue_monthly_aud_100")
                    , ("STRIPE_PRICE_ID", Just "price_direct")
                    , ("STRIPE_MODE", Just "test")
                    , ("STRIPE_BILLING_ENABLED", Just "true")
                    , ("STRIPE_CHECKOUT_ENABLED", Just "true")
                    , ("STRIPE_OWNER_NAVIGATION_VISIBLE", Just "false")
                    , ("APP_BASE_URL", Just "http://localhost:8000")
                    ]
                    do
                        result <- readStripeConfig

                        case result of
                            Left message -> message `shouldBe` "Configure exactly one of STRIPE_PRICE_LOOKUP_KEY or STRIPE_PRICE_ID"
                            Right _ -> expectationFailure "expected ambiguous Stripe Price configuration to be rejected"

            it "rejects live credentials when Stripe is configured for test mode" do
                withStripeEnv
                    [ ("STRIPE_SECRET_KEY_FILE", Nothing)
                    , ("STRIPE_WEBHOOK_SECRET_FILE", Nothing)
                    , ("STRIPE_SECRET_KEY", Just "rk_live_not_a_real_key")
                    , ("STRIPE_WEBHOOK_SECRET", Just "whsec_not_a_real_secret")
                    , ("STRIPE_MODE", Just "test")
                    , ("STRIPE_BILLING_ENABLED", Just "true")
                    , ("STRIPE_CHECKOUT_ENABLED", Just "true")
                    , ("STRIPE_OWNER_NAVIGATION_VISIBLE", Just "false")
                    , ("APP_BASE_URL", Just "http://localhost:8000")
                    ]
                    do
                        result <- readStripeConfig

                        case result of
                            Left message -> message `shouldBe` "Stripe test mode requires a test secret key"
                            Right _ -> expectationFailure "expected live credentials to be rejected in test mode"

            it "requires an HTTPS application base URL in live mode" do
                withStripeEnv
                    [ ("STRIPE_SECRET_KEY_FILE", Nothing)
                    , ("STRIPE_WEBHOOK_SECRET_FILE", Nothing)
                    , ("STRIPE_SECRET_KEY", Just "rk_live_not_a_real_key")
                    , ("STRIPE_WEBHOOK_SECRET", Just "whsec_not_a_real_secret")
                    , ("STRIPE_MODE", Just "live")
                    , ("STRIPE_BILLING_ENABLED", Just "true")
                    , ("STRIPE_CHECKOUT_ENABLED", Just "true")
                    , ("STRIPE_OWNER_NAVIGATION_VISIBLE", Just "false")
                    , ("APP_BASE_URL", Just "http://billing.example.test")
                    ]
                    do
                        result <- readStripeConfig

                        case result of
                            Left message -> message `shouldBe` "Stripe live mode requires an HTTPS APP_BASE_URL"
                            Right _ -> expectationFailure "expected an HTTP live base URL to be rejected"

            it "accepts restricted live credentials and the documented secret-key fallback" do
                forM_ ["rk_live_not_a_real_key", "sk_live_not_a_real_key"] \liveKey ->
                    withStripeEnv
                        [ ("STRIPE_SECRET_KEY_FILE", Nothing)
                        , ("STRIPE_WEBHOOK_SECRET_FILE", Nothing)
                        , ("STRIPE_SECRET_KEY", Just liveKey)
                        , ("STRIPE_WEBHOOK_SECRET", Just "whsec_not_a_real_secret")
                        , ("STRIPE_MODE", Just "live")
                        , ("STRIPE_BILLING_ENABLED", Just "true")
                        , ("STRIPE_CHECKOUT_ENABLED", Just "true")
                        , ("STRIPE_OWNER_NAVIGATION_VISIBLE", Just "false")
                        , ("APP_BASE_URL", Just "https://billing.example.test")
                        ]
                        do
                            result <- readStripeConfig

                            fmap (.stripeMode) result `shouldBe` Right StripeLiveMode

            it "defaults missing deployment controls to disabled" do
                withStripeEnv
                    [ ("STRIPE_BILLING_ENABLED", Nothing)
                    , ("STRIPE_CHECKOUT_ENABLED", Nothing)
                    , ("STRIPE_OWNER_NAVIGATION_VISIBLE", Nothing)
                    ]
                    do
                        readStripeDeploymentControls
                            `shouldReturn` Right
                                StripeDeploymentControls
                                    { stripeBillingEnabled = False
                                    , stripeCheckoutEnabled = False
                                    , stripeOwnerNavigationVisible = False
                                    }

            it "rejects malformed deployment controls" do
                withStripeEnv
                    [ ("STRIPE_BILLING_ENABLED", Just "yes")
                    , ("STRIPE_CHECKOUT_ENABLED", Just "false")
                    , ("STRIPE_OWNER_NAVIGATION_VISIBLE", Just "false")
                    ]
                    do
                        result <- readStripeDeploymentControls

                        result `shouldBe` Left "STRIPE_BILLING_ENABLED must be true or false"

            it "rejects malformed webhook signing credentials" do
                withStripeEnv
                    [ ("STRIPE_SECRET_KEY_FILE", Nothing)
                    , ("STRIPE_WEBHOOK_SECRET_FILE", Nothing)
                    , ("STRIPE_SECRET_KEY", Just "sk_test_not_a_real_key")
                    , ("STRIPE_WEBHOOK_SECRET", Just "not_a_webhook_secret")
                    , ("STRIPE_MODE", Just "test")
                    , ("STRIPE_BILLING_ENABLED", Just "true")
                    , ("STRIPE_CHECKOUT_ENABLED", Just "true")
                    , ("STRIPE_OWNER_NAVIGATION_VISIBLE", Just "false")
                    , ("APP_BASE_URL", Just "http://localhost:8000")
                    ]
                    do
                        result <- readStripeConfig

                        case result of
                            Left message -> message `shouldBe` "Stripe webhook signing secret must start with whsec_"
                            Right _ -> expectationFailure "expected malformed webhook credentials to be rejected"

        describe "process-level test boundary" do
            it "is unavailable unless explicit E2E and test mode are both enabled" do
                let boundaryUrl = "http://127.0.0.1:7199"
                client <- currentStripeClient

                withStripeEnv
                    [ ("STRIPE_TEST_API_BASE_URL", Just boundaryUrl)
                    , ("IHP_ROSTER_E2E", Nothing)
                    , ("STRIPE_MODE", Just "test")
                    ]
                    do
                        client.listPrices testConfig
                            `shouldReturn` Left (StripeHttpError "The local Stripe test boundary is unavailable outside explicit E2E test mode")

                withStripeEnv
                    [ ("STRIPE_TEST_API_BASE_URL", Just boundaryUrl)
                    , ("IHP_ROSTER_E2E", Just "1")
                    , ("STRIPE_MODE", Just "live")
                    ]
                    do
                        client.listPrices testConfig
                            `shouldReturn` Left (StripeHttpError "The local Stripe test boundary is unavailable outside explicit E2E test mode")

            it "fails closed instead of reaching Stripe when explicit E2E mode has no local boundary" do
                client <- currentStripeClient
                withStripeEnv
                    [ ("STRIPE_TEST_API_BASE_URL", Nothing)
                    , ("IHP_ROSTER_E2E", Just "1")
                    , ("STRIPE_MODE", Just "test")
                    ]
                    do
                        client.listPrices testConfig
                            `shouldReturn` Left (StripeHttpError "Explicit E2E mode requires the local Stripe test boundary")

            it "does not follow redirects from the loopback boundary to an external target" do
                client <- currentStripeClient
                let redirectingMock _request respond =
                        respond (Wai.responseLBS status302 [("Location", "https://api.stripe.com/v1/prices")] "")
                Warp.testWithApplication (pure redirectingMock) \port ->
                    withStripeEnv
                        [ ("STRIPE_TEST_API_BASE_URL", Just ("http://127.0.0.1:" <> Text.unpack (tshow port)))
                        , ("IHP_ROSTER_E2E", Just "1")
                        , ("STRIPE_MODE", Just "test")
                        ]
                        do
                            client.listPrices testConfig
                                `shouldReturn` Left (StripeHttpError "Stripe request failed with status 302")

            it "rejects non-loopback and deceptive test-boundary targets before opening a connection" do
                client <- currentStripeClient
                forM_
                    [ "http://stripe.invalid:7199"
                    , "http://127.0.0.1:7199@stripe.invalid"
                    , "http://localhost:7199"
                    , "http://localhost:7199/proxy"
                    ]
                    \testBoundaryUrl ->
                        withStripeEnv
                            [ ("STRIPE_TEST_API_BASE_URL", Just testBoundaryUrl)
                            , ("IHP_ROSTER_E2E", Just "1")
                            , ("STRIPE_MODE", Just "test")
                            ]
                            do
                                client.listPrices testConfig
                                    `shouldReturn` Left (StripeHttpError "The local Stripe test boundary requires an HTTP loopback URL")

        describe "request construction" do
            it "builds active lookup-key price requests" do
                let request = buildListPricesRequest testConfig

                request.stripeRequestMethod `shouldBe` "GET"
                request.stripeRequestUrl `shouldSatisfy` Text.isPrefixOf "https://api.stripe.com/v1/prices?"
                request.stripeRequestUrl `shouldSatisfy` Text.isInfixOf "active=true"
                request.stripeRequestUrl `shouldSatisfy` Text.isInfixOf "lookup_keys%5B%5D=bepis_venue_monthly_aud_100"
                request.stripeRequestUrl `shouldSatisfy` Text.isInfixOf "expand%5B%5D=data.product"
                lookup "Authorization" request.stripeRequestHeaders `shouldBe` Just "Bearer sk_test_123"
                lookup "Stripe-Version" request.stripeRequestHeaders `shouldBe` Just "2026-06-24.dahlia"
                request.stripeRequestTimeoutMicroseconds `shouldBe` 15000000

            it "builds Customer v1 create requests with the initiating owner's verified email" do
                let request = buildCreateCustomerRequest testConfig "venue-123" "Venue Name" "owner@example.test"
                let body = formBody request

                request.stripeRequestMethod `shouldBe` "POST"
                request.stripeRequestUrl `shouldBe` "https://api.stripe.com/v1/customers"
                lookup "Idempotency-Key" request.stripeRequestHeaders `shouldBe` Just "bepis-billing-customer-venue-123"
                lookup "name" body `shouldBe` Just "Venue Name"
                lookup "email" body `shouldBe` Just "owner@example.test"
                lookup "metadata[venue_id]" body `shouldBe` Just "venue-123"
                bodyKeys body `shouldNotSatisfy` any (`List.elem` ["address[line1]", "tax_id_data[0][value]", "payment_method"])

            it "builds hosted subscription Checkout requests with attempt-scoped idempotency" do
                let request =
                        buildCreateCheckoutSessionRequest
                            testConfig
                            "attempt-456"
                            "venue-123"
                            "cus_123"
                            "price_123"
                            "https://app.example.test/BillingSuccess?attempt_id=attempt-456&session_id={CHECKOUT_SESSION_ID}"
                            "https://app.example.test/BillingCancel?attempt_id=attempt-456"
                let body = formBody request

                request.stripeRequestUrl `shouldBe` "https://api.stripe.com/v1/checkout/sessions"
                lookup "Idempotency-Key" request.stripeRequestHeaders `shouldBe` Just "bepis-billing-checkout-attempt-456"
                lookup "mode" body `shouldBe` Just "subscription"
                lookup "customer" body `shouldBe` Just "cus_123"
                lookup "line_items[0][price]" body `shouldBe` Just "price_123"
                lookup "line_items[0][quantity]" body `shouldBe` Just "1"
                lookup "client_reference_id" body `shouldBe` Just "venue-123"
                lookup "metadata[venue_id]" body `shouldBe` Just "venue-123"
                lookup "subscription_data[metadata][venue_id]" body `shouldBe` Just "venue-123"
                lookup "automatic_tax[enabled]" body `shouldBe` Just "false"
                lookup "tax_id_collection[enabled]" body `shouldBe` Just "false"
                bodyKeys body `shouldNotSatisfy` List.elem "payment_method_types[0]"

            it "builds Customer Portal requests with a fresh request-scoped idempotency key" do
                let portalRequest = buildCreatePortalSessionRequest testConfig "request-789" "venue-123" "cus_123" "https://app.example.test/Billing"
                let secondPortalRequest = buildCreatePortalSessionRequest testConfig "request-790" "venue-123" "cus_123" "https://app.example.test/Billing"
                let portalBody = formBody portalRequest

                portalRequest.stripeRequestUrl `shouldBe` "https://api.stripe.com/v1/billing_portal/sessions"
                lookup "Idempotency-Key" portalRequest.stripeRequestHeaders `shouldBe` Just "bepis-billing-portal-venue-123-request-789"
                lookup "Idempotency-Key" secondPortalRequest.stripeRequestHeaders `shouldBe` Just "bepis-billing-portal-venue-123-request-790"
                lookup "customer" portalBody `shouldBe` Just "cus_123"
                lookup "return_url" portalBody `shouldBe` Just "https://app.example.test/Billing"

                (buildRetrieveCheckoutSessionRequest testConfig "cs_test").stripeRequestUrl
                    `shouldBe` "https://api.stripe.com/v1/checkout/sessions/cs_test"
                (buildRetrieveSubscriptionRequest testConfig "sub_test").stripeRequestUrl
                    `shouldBe` "https://api.stripe.com/v1/subscriptions/sub_test"
                (buildRetrievePriceRequest testConfig "price_test").stripeRequestUrl
                    `shouldBe` "https://api.stripe.com/v1/prices/price_test"

        describe "price validation" do
            it "accepts the launch AUD 100 monthly licensed recurring price" do
                validateVenueMonthlyPrice validPrice `shouldBe` Right validPrice

            it "rejects inactive, wrong amount, and metered prices" do
                validateVenueMonthlyPrice validPrice { active = False } `shouldBe` Left "Stripe Price is not active"
                validateVenueMonthlyPrice validPrice { unitAmount = Just 9900 } `shouldBe` Left "Stripe Price unit amount must be AUD 100.00"
                validateVenueMonthlyPrice validPrice { recurring = Just validRecurring { usageType = Just "metered" } }
                    `shouldBe` Left "Stripe Price usage type must be licensed"

        describe "created Checkout response validation" do
            it "requires the requested Customer, subscription mode, and open status" do
                let validSession =
                        StripeCheckoutSession
                            { stripeCheckoutSessionId = "cs_created_123"
                            , stripeCheckoutSessionUrl = Just "https://checkout.stripe.com/c/pay/cs_test_sanitized"
                            , stripeCheckoutCustomerId = Just "cus_expected"
                            , stripeCheckoutSubscriptionId = Nothing
                            , stripeCheckoutClientReferenceId = Just "venue-expected"
                            , stripeCheckoutVenueId = Just "venue-expected"
                            , stripeCheckoutLivemode = False
                            , stripeCheckoutMode = "subscription"
                            , stripeCheckoutStatus = "open"
                            , stripeCheckoutExpiresAt = 1784764800
                            }

                validateCreatedCheckoutSession "cus_expected" validSession `shouldBe` Right validSession
                validateCreatedCheckoutSession "cus_expected" validSession { stripeCheckoutCustomerId = Just "cus_other" }
                    `shouldBe` Left "Stripe Checkout returned an unexpected Customer."
                validateCreatedCheckoutSession "cus_expected" validSession { stripeCheckoutMode = "payment" }
                    `shouldBe` Left "Stripe Checkout returned an unexpected mode."
                validateCreatedCheckoutSession "cus_expected" validSession { stripeCheckoutStatus = "complete" }
                    `shouldBe` Left "Stripe Checkout returned an unexpected status."

            it "validates retrieved Checkout identity, Customer, mode, and status" do
                let retrievedSession =
                        StripeCheckoutSession
                            { stripeCheckoutSessionId = "cs_expected"
                            , stripeCheckoutSessionUrl = Nothing
                            , stripeCheckoutCustomerId = Just "cus_expected"
                            , stripeCheckoutSubscriptionId = Just "sub_expected"
                            , stripeCheckoutClientReferenceId = Just "venue-expected"
                            , stripeCheckoutVenueId = Just "venue-expected"
                            , stripeCheckoutLivemode = False
                            , stripeCheckoutMode = "subscription"
                            , stripeCheckoutStatus = "complete"
                            , stripeCheckoutExpiresAt = 1784764800
                            }

                validateRetrievedCheckoutSession "cs_expected" "cus_expected" retrievedSession `shouldBe` Right retrievedSession
                validateRetrievedCheckoutSession "cs_other" "cus_expected" retrievedSession
                    `shouldBe` Left "Stripe Checkout retrieval returned an unexpected Session."
                validateRetrievedCheckoutSession "cs_expected" "cus_other" retrievedSession
                    `shouldBe` Left "Stripe Checkout retrieval returned an unexpected Customer."
                validateRetrievedCheckoutSession "cs_expected" "cus_expected" retrievedSession { stripeCheckoutMode = "payment" }
                    `shouldBe` Left "Stripe Checkout retrieval returned an unexpected mode."
                validateRetrievedCheckoutSession "cs_expected" "cus_expected" retrievedSession { stripeCheckoutStatus = "invalid" }
                    `shouldBe` Left "Stripe Checkout retrieval returned an unexpected status."

            it "requires the requested Customer and return URL for Customer Portal" do
                let validSession =
                        StripePortalSession
                            { stripePortalSessionId = "bps_created_123"
                            , stripePortalSessionUrl = "https://billing.stripe.com/p/session/bps_test_sanitized"
                            , stripePortalSessionLivemode = False
                            , stripePortalCustomerId = "cus_expected"
                            , stripePortalReturnUrl = "https://app.example.test/Billing"
                            }

                validateCreatedPortalSession "cus_expected" "https://app.example.test/Billing" validSession `shouldBe` Right validSession
                validateCreatedPortalSession "cus_other" "https://app.example.test/Billing" validSession
                    `shouldBe` Left "Stripe Customer Portal returned an unexpected Customer."
                validateCreatedPortalSession "cus_expected" "https://app.example.test/Other" validSession
                    `shouldBe` Left "Stripe Customer Portal returned an unexpected return URL."

        describe "provider error sanitization" do
            it "never exposes provider payloads or credential-like values to callers" do
                stripeClientErrorText (StripeHttpError "card details and sk_live_secret")
                    `shouldBe` "Stripe is temporarily unavailable. Try again."
                stripeClientErrorText (StripeJsonError "customer@example.test at $.billing_details")
                    `shouldBe` "Stripe returned an unexpected response. Try again."

        describe "webhook signatures" do
            it "verifies Stripe signatures against the raw body" do
                let rawBody = "{\"id\":\"evt_test\",\"object\":\"event\"}"
                let header = "t=1700000000,v1=c25fec335f20601dcb662f0e7c4944646158a9324bb6ed8b7f6ab126449f507a"

                verifyStripeWebhookSignatureAt 1700000010 300 "whsec_test" header rawBody
                    `shouldBe` Right
                        StripeWebhookSignature
                            { signatureTimestamp = 1700000000
                            , matchedSignature = "c25fec335f20601dcb662f0e7c4944646158a9324bb6ed8b7f6ab126449f507a"
                            }

            it "rejects mismatched and stale signatures" do
                let rawBody = "{\"id\":\"evt_test\",\"object\":\"event\"}"
                let validHeader = "t=1700000000,v1=c25fec335f20601dcb662f0e7c4944646158a9324bb6ed8b7f6ab126449f507a"

                verifyStripeWebhookSignatureAt 1700000010 300 "wrong_secret" validHeader rawBody
                    `shouldBe` Left "Stripe webhook signature mismatch"
                verifyStripeWebhookSignatureAt 1700000401 300 "whsec_test" validHeader rawBody
                    `shouldBe` Left "Stripe webhook timestamp is outside tolerance"

testConfig :: StripeConfig
testConfig =
    StripeConfig
        { secretKey = "sk_test_123"
        , webhookSecret = "whsec_test_123"
        , priceLookupKey = Just defaultPriceLookupKey
        , priceId = Nothing
        , appBaseUrl = "https://app.example.test"
        , stripeMode = StripeTestMode
        , stripeDeploymentControls = testDeploymentControls
        }

testDeploymentControls :: StripeDeploymentControls
testDeploymentControls =
    StripeDeploymentControls
        { stripeBillingEnabled = True
        , stripeCheckoutEnabled = True
        , stripeOwnerNavigationVisible = False
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

formBody :: StripeHttpRequest -> [(LByteString.ByteString, LByteString.ByteString)]
formBody request =
    case request.stripeRequestBody of
        Just (StripeFormBody body) -> map (Bifunctor.bimap cs cs) body
        Nothing                    -> []

bodyKeys :: [(LByteString.ByteString, LByteString.ByteString)] -> [LByteString.ByteString]
bodyKeys = map fst

withTempSecret :: Text -> (String -> IO a) -> IO a
withTempSecret value action =
    bracket setup cleanup \(path, _) -> action path
    where
        setup = do
            (path, handle) <- openTempFile "/tmp" "stripe-secret"
            TextIO.hPutStr handle value
            hClose handle
            pure (path, handle)

        cleanup (path, _) =
            Directory.removeFile path

withStripeEnv :: [(String, Maybe String)] -> IO a -> IO a
withStripeEnv values action =
    foldr withOne action values
    where
        withOne (name, value) inner =
            withEnv name value inner

withEnv :: String -> Maybe String -> IO a -> IO a
withEnv name value action =
    bracket_ setup restore action
    where
        setup = do
            previous <- Environment.lookupEnv name
            Environment.setEnv ("__PREVIOUS_" <> name) (fromMaybe "" previous)
            Environment.setEnv ("__HAD_PREVIOUS_" <> name) (if isJust previous then "1" else "0")
            apply value

        restore = do
            hadPrevious <- Environment.lookupEnv ("__HAD_PREVIOUS_" <> name)
            previous <- Environment.lookupEnv ("__PREVIOUS_" <> name)
            case (hadPrevious, previous) of
                (Just "1", Just oldValue) -> Environment.setEnv name oldValue
                _                         -> Environment.unsetEnv name
            Environment.unsetEnv ("__PREVIOUS_" <> name)
            Environment.unsetEnv ("__HAD_PREVIOUS_" <> name)

        apply Nothing      = Environment.unsetEnv name
        apply (Just value) = Environment.setEnv name value

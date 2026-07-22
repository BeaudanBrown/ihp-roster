module Test.BillingWebhookSpec where

import Application.Billing.Notifications (billingNotificationJobKind)
import Application.Billing.Stripe
import Application.Billing.Webhook
import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import qualified "crypton" Crypto.Hash as Hash
import "crypton" Crypto.MAC.HMAC (HMAC, hmac)
import qualified Data.Aeson as Aeson
import qualified Data.ByteArray as ByteArray
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LByteString
import qualified Data.IORef as IORef
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Time.Clock.POSIX (getPOSIXTime, posixSecondsToUTCTime)
import qualified Data.Vault.Lazy as Vault
import Generated.Types
import IHP.Controller.Session (sessionVaultKey)
import IHP.ControllerPrelude
import IHP.ControllerSupport (runActionWithNewContext)
import IHP.Server (initMiddlewareStack)
import IHP.Test.Mocking
import Network.HTTP.Types.Header (hContentType)
import Network.HTTP.Types.Status
import qualified Network.Wai as Wai
import Network.Wai.Internal (ResponseReceived (..))
import Test.Hspec
import Test.Support
import Web.Controller.StripeWebhooks ()
import Web.FrontController ()
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "BillingWebhook" do
        it "upserts venue subscription state from subscription lifecycle events" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Subscription Venue"
                _ <- createBillingCustomer venue "cus_subscription_123"

                Right result <- handleStripeWebhookPayload (subscriptionEvent "evt_sub_updated" venue "cus_subscription_123" "sub_123" "active")

                result `shouldSatisfy` isProcessed
                event <- query @BillingEvent |> filterWhere (#stripeEventId, "evt_sub_updated" :: Text) |> fetchOne
                event.status `shouldBe` "processed"
                subscription <- query @VenueSubscription |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                subscription.stripeSubscriptionId `shouldBe` "sub_123"
                subscription.stripePriceId `shouldBe` "price_monthly_123"
                subscription.status `shouldBe` "active"
                subscription.currentPeriodStart `shouldSatisfy` isJust
                subscription.currentPeriodEnd `shouldSatisfy` isJust

        it "stores Dahlia billing periods from the single Subscription Item" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Dahlia Subscription Item Venue"
                _ <- createBillingCustomer venue "cus_dahlia_123"
                eventBody <- LByteString.readFile "Test/Fixtures/stripe/2026-06-24.dahlia/webhook-subscription-updated.json"
                signatureHeader <- signedStripeHeader testStripeConfig.webhookSecret eventBody

                response <- withStripeConfigForTest (Right testStripeConfig) do
                    callStripeWebhookWithJsonBody eventBody signatureHeader

                response `responseStatusShouldBe` status200
                subscription <- query @VenueSubscription |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                subscription.stripeSubscriptionId `shouldBe` "sub_dahlia_123"
                subscription.stripePriceId `shouldBe` "price_monthly_123"
                subscription.currentPeriodStart `shouldBe` Just (posixSecondsToUTCTime 1784678400)
                subscription.currentPeriodEnd `shouldBe` Just (posixSecondsToUTCTime 1787356800)
                subscription.cancelAtPeriodEnd `shouldBe` True

        it "deduplicates already processed Stripe event ids" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Duplicate Venue"
                _ <- createBillingCustomer venue "cus_duplicate_123"
                let eventBody = subscriptionEvent "evt_duplicate_subscription" venue "cus_duplicate_123" "sub_duplicate" "active"

                Right firstResult <- handleStripeWebhookPayload eventBody
                Right secondResult <- handleStripeWebhookPayload eventBody

                firstResult `shouldSatisfy` isProcessed
                secondResult `shouldSatisfy` isDuplicate
                eventCount <- query @BillingEvent |> filterWhere (#stripeEventId, "evt_duplicate_subscription" :: Text) |> fetchCount
                eventCount `shouldBe` 1

        it "records unknown events as ignored without storing raw payloads" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Ignored Venue"

                Right result <- handleStripeWebhookPayload (unknownEvent "evt_unknown_123" venue)

                result `shouldSatisfy` isIgnored
                event <- query @BillingEvent |> filterWhere (#stripeEventId, "evt_unknown_123" :: Text) |> fetchOne
                event.status `shouldBe` "ignored"
                event.providerObjectType `shouldBe` Just "customer"
                event.providerObjectId `shouldBe` Just "cus_ignored_123"

        it "enqueues owner and super-admin notifications for payment problems" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Notification Venue"
                owner <- createUserRecord "billing-problem-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createUserRecordWithPlatformRole "billing-problem-support@example.com" "staff" (Just SuperAdminRole) True
                _ <- createBillingCustomer venue "cus_payment_failed_123"

                Right result <- handleStripeWebhookPayload (invoicePaymentFailedEvent "evt_invoice_failed_123" "cus_payment_failed_123")

                result `shouldSatisfy` isProcessed
                jobs <- query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetch
                length jobs `shouldBe` 2
                map (.venueId) jobs `shouldBe` [Just (unpackId venue.id), Just (unpackId venue.id)]
                map (.relatedTable) jobs `shouldBe` [Just "billing_events", Just "billing_events"]

        it "accepts a valid signed JSON webhook request through the controller body middleware" $ withContext do
            withCleanDb do
                let eventBody = checkoutSessionEventWithoutVenue "evt_controller_checkout_123" "cus_controller_123" "sub_controller_123"
                signatureHeader <- signedStripeHeader testStripeConfig.webhookSecret eventBody
                response <- withStripeConfigForTest (Right testStripeConfig) do
                    callStripeWebhookWithJsonBody eventBody signatureHeader

                response `responseStatusShouldBe` status200
                event <- query @BillingEvent |> filterWhere (#stripeEventId, "evt_controller_checkout_123" :: Text) |> fetchOne
                event.status `shouldBe` "processed"
                event.providerObjectType `shouldBe` Just "checkout.session"
                event.stripeCustomerId `shouldBe` Just "cus_controller_123"
                event.stripeSubscriptionId `shouldBe` Just "sub_controller_123"

        it "rejects signed webhook events from an unexpected Stripe API version" $ withContext do
            withCleanDb do
                let eventBody = checkoutSessionEventWithApiVersion "2026-04-22.dahlia" "evt_outdated_api_version" "cus_outdated_123" "sub_outdated_123"
                signatureHeader <- signedStripeHeader testStripeConfig.webhookSecret eventBody

                response <- withStripeConfigForTest (Right testStripeConfig) do
                    callStripeWebhookWithJsonBody eventBody signatureHeader

                response `responseStatusShouldBe` status400
                eventCount <- query @BillingEvent |> fetchCount
                eventCount `shouldBe` 0

        it "upserts subscription state from a signed controller webhook request" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Controller Subscription Venue"
                let eventBody = subscriptionEvent "evt_controller_subscription_123" venue "cus_controller_subscription_123" "sub_controller_subscription_123" "active"
                signatureHeader <- signedStripeHeader testStripeConfig.webhookSecret eventBody
                response <- withStripeConfigForTest (Right testStripeConfig) do
                    callStripeWebhookWithJsonBody eventBody signatureHeader

                response `responseStatusShouldBe` status200
                event <- query @BillingEvent |> filterWhere (#stripeEventId, "evt_controller_subscription_123" :: Text) |> fetchOne
                event.status `shouldBe` "processed"
                event.venueId `shouldBe` Just (unpackId venue.id)
                subscription <- query @VenueSubscription |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                subscription.stripeSubscriptionId `shouldBe` "sub_controller_subscription_123"
                subscription.stripePriceId `shouldBe` "price_monthly_123"
                subscription.status `shouldBe` "active"

        it "rejects invalid webhook signatures before parsing" $ withContext do
            withCleanDb do
                response <- withStripeConfigForTest (Right testStripeConfig) do
                    withRequestHeaders [("Stripe-Signature", "t=1700000000,v1=bad")] do
                        callAction StripeWebhookAction

                response `responseStatusShouldBe` status400
                eventCount <- query @BillingEvent |> fetchCount
                eventCount `shouldBe` 0

        it "rejects signed JSON webhook requests when the body bytes do not match the signature" $ withContext do
            withCleanDb do
                let signedBody = checkoutSessionEventWithoutVenue "evt_body_mismatch_signed" "cus_body_mismatch" "sub_body_mismatch"
                let sentBody = checkoutSessionEventWithoutVenue "evt_body_mismatch_sent" "cus_body_mismatch" "sub_body_mismatch"
                signatureHeader <- signedStripeHeader testStripeConfig.webhookSecret signedBody
                response <- withStripeConfigForTest (Right testStripeConfig) do
                    callStripeWebhookWithJsonBody sentBody signatureHeader

                response `responseStatusShouldBe` status400
                eventCount <- query @BillingEvent |> fetchCount
                eventCount `shouldBe` 0

callStripeWebhookWithJsonBody :: (?application :: WebApplication, ?mocking :: MockContext WebApplication, ?request :: Wai.Request) => LByteString.ByteString -> Text -> IO Wai.Response
callStripeWebhookWithJsonBody rawBody signatureHeader = do
    let MockContext { frameworkConfig, modelContext, pgListener } = ?mocking
    requestChunks <- IORef.newIORef (LByteString.toChunks rawBody)
    let readBodyChunk = IORef.atomicModifyIORef requestChunks \case
            [] -> ([], "")
            chunk : chunks -> (chunks, chunk)
    let baseRequest =
            (Wai.setRequestBodyChunks readBodyChunk ?request)
                { Wai.requestMethod = "POST"
                , Wai.requestHeaders =
                    [ (hContentType, "application/json")
                    , ("Stripe-Signature", cs signatureHeader)
                    ] <> filter ((/= hContentType) . fst) (Wai.requestHeaders ?request)
                }
    responseRef <- IORef.newIORef Nothing
    let captureRespond response = do
            IORef.writeIORef responseRef (Just response)
            pure ResponseReceived
    let mockSession = Vault.lookup sessionVaultKey (Wai.vault ?request)
    let controllerApp request respond = do
            let request' = case mockSession of
                    Just session -> request { Wai.vault = Vault.insert sessionVaultKey session (Wai.vault request) }
                    Nothing -> request
            let ?request = request'
            let ?respond = respond
            runActionWithNewContext StripeWebhookAction
    middlewareStack <- initMiddlewareStack frameworkConfig modelContext pgListener
    _ <- middlewareStack controllerApp baseRequest captureRespond
    IORef.readIORef responseRef >>= \case
        Just response -> pure response
        Nothing -> error "callStripeWebhookWithJsonBody: No response was returned by the controller"

signedStripeHeader :: Text -> LByteString.ByteString -> IO Text
signedStripeHeader webhookSecret rawBody = do
    timestamp <- floor <$> getPOSIXTime
    let signature = stripeWebhookTestSignatureHex webhookSecret timestamp rawBody
    pure ("t=" <> cs (show timestamp) <> ",v1=" <> signature)

stripeWebhookTestSignatureHex :: Text -> Integer -> LByteString.ByteString -> Text
stripeWebhookTestSignatureHex webhookSecret timestamp rawBody =
    let digest = hmac (TextEncoding.encodeUtf8 webhookSecret) (stripeWebhookSignedPayload timestamp rawBody) :: HMAC Hash.SHA256
     in bytesToHex (ByteArray.convert digest)

bytesToHex :: ByteString.ByteString -> Text
bytesToHex = Text.concat . map byteToHex . ByteString.unpack
    where
        byteToHex byte =
            let high = fromIntegral byte `div` (16 :: Int)
                low = fromIntegral byte `mod` (16 :: Int)
             in Text.pack [hexDigit high, hexDigit low]

        hexDigit value
            | value < 10 = toEnum (fromEnum '0' + value)
            | otherwise = toEnum (fromEnum 'a' + value - 10)

createBillingCustomer :: (?modelContext :: ModelContext) => Venue -> Text -> IO VenueBillingCustomer
createBillingCustomer venue customerId =
    newRecord @VenueBillingCustomer
        |> set #venueId (unpackId venue.id)
        |> set #stripeCustomerId customerId
        |> createRecord

subscriptionEvent :: Text -> Venue -> Text -> Text -> Text -> LByteString.ByteString
subscriptionEvent eventId venue customerId subscriptionId status =
    Aeson.encode $
        Aeson.object
            [ "id" Aeson..= eventId
            , "type" Aeson..= ("customer.subscription.updated" :: Text)
            , "livemode" Aeson..= False
            , "api_version" Aeson..= pinnedStripeApiVersion
            , "data" Aeson..=
                Aeson.object
                    [ "object" Aeson..=
                        Aeson.object
                            [ "object" Aeson..= ("subscription" :: Text)
                            , "id" Aeson..= subscriptionId
                            , "customer" Aeson..= customerId
                            , "livemode" Aeson..= False
                            , "status" Aeson..= status
                            , "cancel_at_period_end" Aeson..= False
                            , "metadata" Aeson..= Aeson.object ["venue_id" Aeson..= inputValue venue.id]
                            , "items" Aeson..=
                                Aeson.object
                                    [ "data" Aeson..=
                                        [ Aeson.object
                                            [ "current_period_start" Aeson..= (1760000000 :: Integer)
                                            , "current_period_end" Aeson..= (1762592000 :: Integer)
                                            , "price" Aeson..= monthlyPriceObject
                                            , "quantity" Aeson..= (1 :: Int)
                                            ]
                                        ]
                                    ]
                            ]
                    ]
            ]
  where
    monthlyPriceObject =
        Aeson.object
            [ "id" Aeson..= ("price_monthly_123" :: Text)
            , "active" Aeson..= True
            , "currency" Aeson..= ("aud" :: Text)
            , "livemode" Aeson..= False
            , "unit_amount" Aeson..= (10000 :: Int)
            , "type" Aeson..= ("recurring" :: Text)
            , "recurring" Aeson..=
                Aeson.object
                    [ "interval" Aeson..= ("month" :: Text)
                    , "interval_count" Aeson..= (1 :: Int)
                    , "usage_type" Aeson..= ("licensed" :: Text)
                    ]
            ]

checkoutSessionEventWithoutVenue :: Text -> Text -> Text -> LByteString.ByteString
checkoutSessionEventWithoutVenue = checkoutSessionEventWithApiVersion pinnedStripeApiVersion

checkoutSessionEventWithApiVersion :: Text -> Text -> Text -> Text -> LByteString.ByteString
checkoutSessionEventWithApiVersion apiVersion eventId customerId subscriptionId =
    Aeson.encode $
        Aeson.object
            [ "id" Aeson..= eventId
            , "type" Aeson..= ("checkout.session.completed" :: Text)
            , "livemode" Aeson..= False
            , "api_version" Aeson..= apiVersion
            , "data" Aeson..=
                Aeson.object
                    [ "object" Aeson..=
                        Aeson.object
                            [ "object" Aeson..= ("checkout.session" :: Text)
                            , "id" Aeson..= ("cs_controller_123" :: Text)
                            , "customer" Aeson..= customerId
                            , "subscription" Aeson..= subscriptionId
                            , "status" Aeson..= ("complete" :: Text)
                            ]
                    ]
            ]

invoicePaymentFailedEvent :: Text -> Text -> LByteString.ByteString
invoicePaymentFailedEvent eventId customerId =
    Aeson.encode $
        Aeson.object
            [ "id" Aeson..= eventId
            , "type" Aeson..= ("invoice.payment_failed" :: Text)
            , "livemode" Aeson..= False
            , "api_version" Aeson..= pinnedStripeApiVersion
            , "data" Aeson..=
                Aeson.object
                    [ "object" Aeson..=
                        Aeson.object
                            [ "object" Aeson..= ("invoice" :: Text)
                            , "id" Aeson..= ("in_failed_123" :: Text)
                            , "customer" Aeson..= customerId
                            , "subscription" Aeson..= ("sub_failed_123" :: Text)
                            ]
                    ]
            ]

unknownEvent :: Text -> Venue -> LByteString.ByteString
unknownEvent eventId venue =
    Aeson.encode $
        Aeson.object
            [ "id" Aeson..= eventId
            , "type" Aeson..= ("customer.created" :: Text)
            , "livemode" Aeson..= False
            , "api_version" Aeson..= pinnedStripeApiVersion
            , "data" Aeson..=
                Aeson.object
                    [ "object" Aeson..=
                        Aeson.object
                            [ "object" Aeson..= ("customer" :: Text)
                            , "id" Aeson..= ("cus_ignored_123" :: Text)
                            , "metadata" Aeson..= Aeson.object ["venue_id" Aeson..= inputValue venue.id]
                            ]
                    ]
            ]

testStripeConfig :: StripeConfig
testStripeConfig =
    StripeConfig
        { secretKey = "sk_test_redacted"
        , webhookSecret = "whsec_test"
        , priceLookupKey = Just defaultPriceLookupKey
        , priceId = Nothing
        , appBaseUrl = "http://localhost"
        }

isProcessed :: BillingWebhookResult -> Bool
isProcessed (BillingWebhookProcessed _) = True
isProcessed _                           = False

isDuplicate :: BillingWebhookResult -> Bool
isDuplicate (BillingWebhookDuplicate _) = True
isDuplicate _                           = False

isIgnored :: BillingWebhookResult -> Bool
isIgnored (BillingWebhookIgnored _) = True
isIgnored _                         = False

module Test.BillingWebhookSpec where

import Application.Billing.Notifications (billingNotificationJobKind)
import Application.Billing.Stripe
import Application.Billing.Webhook
import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LByteString
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Test.Hspec
import Test.Support
import Web.Controller.StripeWebhooks ()
import Web.FrontController ()
import Web.Types

tests :: Spec
tests = beforeAll testContext do
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

        it "rejects invalid webhook signatures before parsing" $ withContext do
            withCleanDb do
                response <- withStripeConfigForTest (Right testStripeConfig) do
                    withRequestHeaders [("Stripe-Signature", "t=1700000000,v1=bad")] do
                        callAction StripeWebhookAction

                response `responseStatusShouldBe` status400
                eventCount <- query @BillingEvent |> fetchCount
                eventCount `shouldBe` 0

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
            , "api_version" Aeson..= ("2025-03-31.basil" :: Text)
            , "data" Aeson..=
                Aeson.object
                    [ "object" Aeson..=
                        Aeson.object
                            [ "object" Aeson..= ("subscription" :: Text)
                            , "id" Aeson..= subscriptionId
                            , "customer" Aeson..= customerId
                            , "status" Aeson..= status
                            , "current_period_start" Aeson..= (1760000000 :: Integer)
                            , "current_period_end" Aeson..= (1762592000 :: Integer)
                            , "cancel_at_period_end" Aeson..= False
                            , "metadata" Aeson..= Aeson.object ["venue_id" Aeson..= inputValue venue.id]
                            , "items" Aeson..=
                                Aeson.object
                                    [ "data" Aeson..=
                                        [ Aeson.object
                                            [ "price" Aeson..= Aeson.object ["id" Aeson..= ("price_monthly_123" :: Text)]
                                            ]
                                        ]
                                    ]
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

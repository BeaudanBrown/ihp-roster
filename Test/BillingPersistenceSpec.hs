module Test.BillingPersistenceSpec where

import Control.Exception (SomeException, try)
import Data.Either (isLeft)
import Data.Time.Clock (getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (unpackId)
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests = beforeAll testContext do
    describe "Billing persistence" do
        it "stores venue-scoped Stripe identifiers and manual controls without payment details" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Venue"
                owner <- createUserRecord "billing-owner@example.com" "admin" True
                now <- getCurrentTime

                customer <-
                    newRecord @VenueBillingCustomer
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeCustomerId "cus_billing_123"
                        |> createRecord

                subscription <-
                    newRecord @VenueSubscription
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeSubscriptionId "sub_billing_123"
                        |> set #stripePriceId "price_bepis_monthly"
                        |> set #status "active"
                        |> set #currentPeriodStart (Just now)
                        |> set #currentPeriodEnd (Just now)
                        |> createRecord

                event <-
                    newRecord @BillingEvent
                        |> set #stripeEventId "evt_billing_123"
                        |> set #eventType "customer.subscription.updated"
                        |> set #venueId (Just (unpackId venue.id))
                        |> set #stripeCustomerId (Just customer.stripeCustomerId)
                        |> set #stripeSubscriptionId (Just subscription.stripeSubscriptionId)
                        |> set #status "processed"
                        |> set #processedAt (Just now)
                        |> createRecord

                control <-
                    newRecord @VenueBillingControl
                        |> set #venueId (unpackId venue.id)
                        |> set #manualReadOnly True
                        |> set #manualReadOnlyReason (Just "Payment follow-up")
                        |> set #setByUserId (Just (unpackId owner.id))
                        |> set #setAt (Just now)
                        |> createRecord

                customer.stripeCustomerId `shouldBe` "cus_billing_123"
                subscription.status `shouldBe` "active"
                event.status `shouldBe` "processed"
                control.manualReadOnly `shouldBe` True

        it "enforces one billing customer and one subscription per venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Unique Venue"

                _ <-
                    newRecord @VenueBillingCustomer
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeCustomerId "cus_unique_1"
                        |> createRecord

                duplicateCustomer <-
                    try
                        ( newRecord @VenueBillingCustomer
                            |> set #venueId (unpackId venue.id)
                            |> set #stripeCustomerId "cus_unique_2"
                            |> createRecord
                        ) :: IO (Either SomeException VenueBillingCustomer)

                _ <-
                    newRecord @VenueSubscription
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeSubscriptionId "sub_unique_1"
                        |> set #stripePriceId "price_unique"
                        |> set #status "active"
                        |> createRecord

                duplicateSubscription <-
                    try
                        ( newRecord @VenueSubscription
                            |> set #venueId (unpackId venue.id)
                            |> set #stripeSubscriptionId "sub_unique_2"
                            |> set #stripePriceId "price_unique"
                            |> set #status "past_due"
                            |> createRecord
                        ) :: IO (Either SomeException VenueSubscription)

                duplicateCustomer `shouldSatisfy` isLeft
                duplicateSubscription `shouldSatisfy` isLeft

        it "deduplicates Stripe events by event id" $ withContext do
            withCleanDb do
                _ <-
                    newRecord @BillingEvent
                        |> set #stripeEventId "evt_duplicate"
                        |> set #eventType "invoice.payment_failed"
                        |> createRecord

                duplicateEvent <-
                    try
                        ( newRecord @BillingEvent
                            |> set #stripeEventId "evt_duplicate"
                            |> set #eventType "invoice.payment_failed"
                            |> createRecord
                        ) :: IO (Either SomeException BillingEvent)

                duplicateEvent `shouldSatisfy` isLeft

        it "rejects invalid local billing states" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Constraint Venue"

                invalidSubscriptionStatus <-
                    try
                        ( newRecord @VenueSubscription
                            |> set #venueId (unpackId venue.id)
                            |> set #stripeSubscriptionId "sub_invalid_status"
                            |> set #stripePriceId "price_invalid_status"
                            |> set #status "unknown"
                            |> createRecord
                        ) :: IO (Either SomeException VenueSubscription)

                processedWithoutTimestamp <-
                    try
                        ( newRecord @BillingEvent
                            |> set #stripeEventId "evt_missing_processed_at"
                            |> set #eventType "customer.subscription.updated"
                            |> set #status "processed"
                            |> createRecord
                        ) :: IO (Either SomeException BillingEvent)

                readOnlyWithoutAuditFields <-
                    try
                        ( newRecord @VenueBillingControl
                            |> set #venueId (unpackId venue.id)
                            |> set #manualReadOnly True
                            |> createRecord
                        ) :: IO (Either SomeException VenueBillingControl)

                invalidSubscriptionStatus `shouldSatisfy` isLeft
                processedWithoutTimestamp `shouldSatisfy` isLeft
                readOnlyWithoutAuditFields `shouldSatisfy` isLeft

module Test.BillingPersistenceSpec where

import Control.Exception (SomeException, try)
import Data.Either (isLeft)
import qualified Data.Text as Text
import Data.Time.Clock (addUTCTime, getCurrentTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import qualified Database.PostgreSQL.Simple as PG
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlQuery, unpackId)
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Billing persistence" do
        it "stores venue-scoped Stripe identifiers and manual controls without payment details" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Venue"
                owner <- createUserRecord "billing-owner@example.com" "admin" True
                now <- getCurrentTime
                let providerEventCreatedAt = posixSecondsToUTCTime 1784761200

                customer <-
                    newRecord @VenueBillingCustomer
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeCustomerId "cus_billing_123"
                        |> set #livemode False
                        |> set #createdByUserId (Just (unpackId owner.id))
                        |> createRecord

                subscription <-
                    newRecord @VenueSubscription
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeSubscriptionId "sub_billing_123"
                        |> set #stripePriceId "price_bepis_monthly"
                        |> set #livemode False
                        |> set #status "active"
                        |> set #currentPeriodStart (Just now)
                        |> set #currentPeriodEnd (Just now)
                        |> set #lastAppliedStripeEventCreatedAt (Just providerEventCreatedAt)
                        |> set #lastAppliedStripeEventId (Just "evt_billing_123")
                        |> createRecord

                event <-
                    newRecord @BillingEvent
                        |> set #stripeEventId "evt_billing_123"
                        |> set #eventType "customer.subscription.updated"
                        |> set #livemode False
                        |> set #venueId (Just (unpackId venue.id))
                        |> set #stripeCustomerId (Just customer.stripeCustomerId)
                        |> set #stripeSubscriptionId (Just subscription.stripeSubscriptionId)
                        |> set #stripeCreatedAt (Just providerEventCreatedAt)
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
                customer.livemode `shouldBe` False
                customer.createdByUserId `shouldBe` Just (unpackId owner.id)
                subscription.status `shouldBe` "active"
                subscription.livemode `shouldBe` False
                subscription.lastAppliedStripeEventCreatedAt `shouldBe` Just providerEventCreatedAt
                subscription.lastAppliedStripeEventId `shouldBe` Just "evt_billing_123"
                event.status `shouldBe` "processed"
                event.stripeCreatedAt `shouldBe` Just providerEventCreatedAt
                control.manualReadOnly `shouldBe` True

        it "requires a complete bounded subscription event-ordering cursor" $ withContext do
            withCleanDb do
                missingTimeVenue <- createVenueWithConfig "Ordering Cursor Missing Time"
                missingIdVenue <- createVenueWithConfig "Ordering Cursor Missing ID"
                oversizedIdVenue <- createVenueWithConfig "Ordering Cursor Oversized ID"
                let providerEventCreatedAt = posixSecondsToUTCTime 1784761200

                missingTime <-
                    try
                        ( newRecord @VenueSubscription
                            |> set #venueId (unpackId missingTimeVenue.id)
                            |> set #stripeSubscriptionId "sub_ordering_missing_time"
                            |> set #stripePriceId "price_ordering_missing_time"
                            |> set #livemode False
                            |> set #status "active"
                            |> set #lastAppliedStripeEventId (Just "evt_ordering_missing_time")
                            |> createRecord
                        ) :: IO (Either SomeException VenueSubscription)

                missingId <-
                    try
                        ( newRecord @VenueSubscription
                            |> set #venueId (unpackId missingIdVenue.id)
                            |> set #stripeSubscriptionId "sub_ordering_missing_id"
                            |> set #stripePriceId "price_ordering_missing_id"
                            |> set #livemode False
                            |> set #status "active"
                            |> set #lastAppliedStripeEventCreatedAt (Just providerEventCreatedAt)
                            |> createRecord
                        ) :: IO (Either SomeException VenueSubscription)

                oversizedId <-
                    try
                        ( newRecord @VenueSubscription
                            |> set #venueId (unpackId oversizedIdVenue.id)
                            |> set #stripeSubscriptionId "sub_ordering_oversized_id"
                            |> set #stripePriceId "price_ordering_oversized_id"
                            |> set #livemode False
                            |> set #status "active"
                            |> set #lastAppliedStripeEventCreatedAt (Just providerEventCreatedAt)
                            |> set #lastAppliedStripeEventId (Just (Text.replicate 256 "x"))
                            |> createRecord
                        ) :: IO (Either SomeException VenueSubscription)

                missingTime `shouldSatisfy` isLeft
                missingId `shouldSatisfy` isLeft
                oversizedId `shouldSatisfy` isLeft

        it "stores a durable venue-scoped Checkout attempt without hosted or payment data" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Checkout Attempt Venue"
                owner <- createUserRecord "checkout-attempt-owner@example.com" "admin" True
                now <- getCurrentTime

                attempt <-
                    checkoutAttemptFor venue owner
                        |> set #stripeCustomerId "cus_attempt_123"
                        |> set #stripePriceId "price_attempt_123"
                        |> set #stripeCheckoutSessionId (Just "cs_attempt_123")
                        |> set #expiresAt (Just (addUTCTime 3600 now))
                        |> createRecord

                attempt.venueId `shouldBe` unpackId venue.id
                attempt.initiatedByUserId `shouldBe` unpackId owner.id
                attempt.livemode `shouldBe` False
                attempt.stripeCheckoutSessionId `shouldBe` Just "cs_attempt_123"
                attempt.stripeSubscriptionId `shouldBe` Nothing
                attempt.status `shouldBe` "open"
                attempt.completedAt `shouldBe` Nothing
                attempt.errorCode `shouldBe` Nothing
                attempt.errorSummary `shouldBe` Nothing

        it "exposes only operational Checkout-attempt persistence fields" $ withContext do
            columns :: [PG.Only Text] <-
                sqlQuery
                    "SELECT column_name::text FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'billing_checkout_attempts' ORDER BY ordinal_position"
                    ()

            map PG.fromOnly columns
                `shouldBe`
                    [ "id"
                    , "venue_id"
                    , "initiated_by_user_id"
                    , "livemode"
                    , "stripe_customer_id"
                    , "stripe_price_id"
                    , "stripe_checkout_session_id"
                    , "stripe_subscription_id"
                    , "status"
                    , "expires_at"
                    , "completed_at"
                    , "error_code"
                    , "error_summary"
                    , "created_at"
                    , "updated_at"
                    ]

        it "requires explicit provider mode on new billing records" $ withContext do
            modeDefaults :: [(Text, Maybe Text)] <-
                sqlQuery
                    "SELECT table_name::text, column_default::text FROM information_schema.columns WHERE table_schema = 'public' AND column_name = 'livemode' AND table_name IN ('billing_checkout_attempts', 'billing_events', 'venue_billing_customers', 'venue_subscriptions') ORDER BY table_name"
                    ()

            modeDefaults
                `shouldBe`
                    [ ("billing_checkout_attempts", Nothing)
                    , ("billing_events", Nothing)
                    , ("venue_billing_customers", Nothing)
                    , ("venue_subscriptions", Nothing)
                    ]

        it "allows at most one open Checkout attempt per venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Single Open Checkout Venue"
                owner <- createUserRecord "single-open-checkout@example.com" "admin" True

                firstAttempt <-
                    checkoutAttemptFor venue owner
                        |> set #stripeCheckoutSessionId (Just "cs_single_open_1")
                        |> createRecord

                duplicateOpenAttempt <-
                    try
                        ( checkoutAttemptFor venue owner
                            |> set #stripeCheckoutSessionId (Just "cs_single_open_2")
                            |> createRecord
                        ) :: IO (Either SomeException BillingCheckoutAttempt)

                duplicateOpenAttempt `shouldSatisfy` isLeft

                _ <- firstAttempt |> set #status "failed" |> updateRecord
                replacementAttempt <-
                    checkoutAttemptFor venue owner
                        |> set #stripeCheckoutSessionId (Just "cs_single_open_2")
                        |> createRecord

                replacementAttempt.status `shouldBe` "open"

        it "deduplicates persisted Stripe Checkout Session identifiers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Unique Checkout Session Venue"
                owner <- createUserRecord "unique-checkout-session@example.com" "admin" True

                _ <-
                    checkoutAttemptFor venue owner
                        |> set #stripeCheckoutSessionId (Just "cs_globally_unique")
                        |> set #status "failed"
                        |> createRecord

                duplicateSessionAttempt <-
                    try
                        ( checkoutAttemptFor venue owner
                            |> set #stripeCheckoutSessionId (Just "cs_globally_unique")
                            |> createRecord
                        ) :: IO (Either SomeException BillingCheckoutAttempt)

                duplicateSessionAttempt `shouldSatisfy` isLeft

        it "rejects unknown Checkout attempt statuses" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Checkout Status Constraint Venue"
                owner <- createUserRecord "checkout-status-constraint@example.com" "admin" True

                invalidStatus <-
                    try
                        ( checkoutAttemptFor venue owner
                            |> set #status "unknown"
                            |> createRecord
                        ) :: IO (Either SomeException BillingCheckoutAttempt)

                invalidStatus `shouldSatisfy` isLeft

        it "keeps Checkout completion status and timestamp consistent" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Checkout Completion Constraint Venue"
                owner <- createUserRecord "checkout-completion-constraint@example.com" "admin" True
                now <- getCurrentTime

                completedWithoutTimestamp <-
                    try
                        ( checkoutAttemptFor venue owner
                            |> set #stripeCheckoutSessionId (Just "cs_missing_completion_time")
                            |> set #status "completed"
                            |> createRecord
                        ) :: IO (Either SomeException BillingCheckoutAttempt)

                openWithCompletionTimestamp <-
                    try
                        ( checkoutAttemptFor venue owner
                            |> set #stripeCheckoutSessionId (Just "cs_open_with_completion_time")
                            |> set #completedAt (Just now)
                            |> createRecord
                        ) :: IO (Either SomeException BillingCheckoutAttempt)

                completedWithoutTimestamp `shouldSatisfy` isLeft
                openWithCompletionTimestamp `shouldSatisfy` isLeft

        it "bounds sanitized Checkout failure metadata" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Checkout Failure Metadata Venue"
                owner <- createUserRecord "checkout-failure-metadata@example.com" "admin" True

                oversizedErrorCode <-
                    try
                        ( checkoutAttemptFor venue owner
                            |> set #status "failed"
                            |> set #errorCode (Just (Text.replicate 121 "x"))
                            |> createRecord
                        ) :: IO (Either SomeException BillingCheckoutAttempt)

                oversizedErrorSummary <-
                    try
                        ( checkoutAttemptFor venue owner
                            |> set #status "failed"
                            |> set #errorSummary (Just (Text.replicate 1001 "x"))
                            |> createRecord
                        ) :: IO (Either SomeException BillingCheckoutAttempt)

                blankErrorSummary <-
                    try
                        ( checkoutAttemptFor venue owner
                            |> set #status "failed"
                            |> set #errorSummary (Just "   ")
                            |> createRecord
                        ) :: IO (Either SomeException BillingCheckoutAttempt)

                oversizedErrorCode `shouldSatisfy` isLeft
                oversizedErrorSummary `shouldSatisfy` isLeft
                blankErrorSummary `shouldSatisfy` isLeft

        it "rejects blank or oversized Checkout provider identifiers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Checkout Identifier Constraint Venue"
                owner <- createUserRecord "checkout-identifier-constraint@example.com" "admin" True

                blankCustomerId <-
                    try
                        ( checkoutAttemptFor venue owner
                            |> set #stripeCustomerId "   "
                            |> set #status "failed"
                            |> createRecord
                        ) :: IO (Either SomeException BillingCheckoutAttempt)

                oversizedPriceId <-
                    try
                        ( checkoutAttemptFor venue owner
                            |> set #stripePriceId (Text.replicate 256 "x")
                            |> set #status "failed"
                            |> createRecord
                        ) :: IO (Either SomeException BillingCheckoutAttempt)

                blankSessionId <-
                    try
                        ( checkoutAttemptFor venue owner
                            |> set #stripeCheckoutSessionId (Just "   ")
                            |> set #status "failed"
                            |> createRecord
                        ) :: IO (Either SomeException BillingCheckoutAttempt)

                oversizedSubscriptionId <-
                    try
                        ( checkoutAttemptFor venue owner
                            |> set #stripeSubscriptionId (Just (Text.replicate 256 "x"))
                            |> set #status "failed"
                            |> createRecord
                        ) :: IO (Either SomeException BillingCheckoutAttempt)

                blankCustomerId `shouldSatisfy` isLeft
                oversizedPriceId `shouldSatisfy` isLeft
                blankSessionId `shouldSatisfy` isLeft
                oversizedSubscriptionId `shouldSatisfy` isLeft

        it "enforces one billing customer and one subscription per venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Unique Venue"

                _ <-
                    newRecord @VenueBillingCustomer
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeCustomerId "cus_unique_1"
                        |> set #livemode False
                        |> createRecord

                duplicateCustomer <-
                    try
                        ( newRecord @VenueBillingCustomer
                            |> set #venueId (unpackId venue.id)
                            |> set #stripeCustomerId "cus_unique_2"
                            |> set #livemode False
                            |> createRecord
                        ) :: IO (Either SomeException VenueBillingCustomer)

                _ <-
                    newRecord @VenueSubscription
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeSubscriptionId "sub_unique_1"
                        |> set #stripePriceId "price_unique"
                        |> set #livemode False
                        |> set #status "active"
                        |> createRecord

                duplicateSubscription <-
                    try
                        ( newRecord @VenueSubscription
                            |> set #venueId (unpackId venue.id)
                            |> set #stripeSubscriptionId "sub_unique_2"
                            |> set #stripePriceId "price_unique"
                            |> set #livemode False
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
                        |> set #livemode False
                        |> createRecord

                duplicateEvent <-
                    try
                        ( newRecord @BillingEvent
                            |> set #stripeEventId "evt_duplicate"
                            |> set #eventType "invoice.payment_failed"
                            |> set #livemode False
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
                            |> set #livemode False
                            |> set #status "unknown"
                            |> createRecord
                        ) :: IO (Either SomeException VenueSubscription)

                processedWithoutTimestamp <-
                    try
                        ( newRecord @BillingEvent
                            |> set #stripeEventId "evt_missing_processed_at"
                            |> set #eventType "customer.subscription.updated"
                            |> set #livemode False
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

checkoutAttemptFor :: Venue -> User -> BillingCheckoutAttempt
checkoutAttemptFor venue owner =
    newRecord @BillingCheckoutAttempt
        |> set #venueId (unpackId venue.id)
        |> set #initiatedByUserId (unpackId owner.id)
        |> set #livemode False
        |> set #stripeCustomerId "cus_checkout_attempt"
        |> set #stripePriceId "price_checkout_attempt"

module Test.BillingWebhookSpec where

import Application.Async.Queue (appJobMaxAttempts)
import Application.Async.Registry (dispatchAppJob)
import Application.Billing.Notifications (billingNotificationJobKind,
                                          performBillingNotificationJob)
import Application.Billing.Stripe
import Application.Billing.Webhook
import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import Config (config)
import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, takeMVar)
import Control.Exception (SomeException, try)
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
import IHP.FrameworkConfig (withFrameworkConfig)
import IHP.Job.Types (JobStatus (JobStatusFailed, JobStatusRunning, JobStatusSucceeded, JobStatusTimedOut))
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

                Right result <- handleStripeWebhookPayload StripeTestMode (subscriptionEvent "evt_sub_updated" venue "cus_subscription_123" "sub_123" "active")

                result `shouldSatisfy` isProcessed
                event <- query @BillingEvent |> filterWhere (#stripeEventId, "evt_sub_updated" :: Text) |> fetchOne
                event.status `shouldBe` "processed"
                event.stripeCreatedAt `shouldBe` Just (posixSecondsToUTCTime 1784678460)
                subscription <- query @VenueSubscription |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                subscription.stripeSubscriptionId `shouldBe` "sub_123"
                subscription.stripePriceId `shouldBe` "price_monthly_123"
                subscription.status `shouldBe` "active"
                subscription.currentPeriodStart `shouldSatisfy` isJust
                subscription.currentPeriodEnd `shouldSatisfy` isJust
                subscription.lastAppliedStripeEventCreatedAt `shouldBe` Just (posixSecondsToUTCTime (fromInteger testStripeEventCreatedSeconds))
                subscription.lastAppliedStripeEventId `shouldBe` Just "evt_sub_updated"

        it "does not let an older subscription snapshot regress newer local state" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Ordered Subscription Venue"
                _ <- createBillingCustomer venue "cus_ordered_subscription_123"
                let newerEvent = subscriptionEventAt (testStripeEventCreatedSeconds + 1) "evt_ordered_newer" venue "cus_ordered_subscription_123" "sub_ordered_123" "active"
                let olderEvent = subscriptionEventAt testStripeEventCreatedSeconds "evt_ordered_older" venue "cus_ordered_subscription_123" "sub_ordered_123" "canceled"

                Right _ <- handleStripeWebhookPayload StripeTestMode newerEvent
                Right _ <- handleStripeWebhookPayload StripeTestMode olderEvent

                subscription <- query @VenueSubscription |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                subscription.status `shouldBe` "active"
                subscription.lastAppliedStripeEventCreatedAt `shouldBe` Just (posixSecondsToUTCTime (fromInteger (testStripeEventCreatedSeconds + 1)))
                subscription.lastAppliedStripeEventId `shouldBe` Just "evt_ordered_newer"
                eventCount <- query @BillingEvent |> fetchCount
                eventCount `shouldBe` 2

        it "completes the matching Checkout attempt from a completed Checkout event" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Checkout Attempt Venue"
                owner <- createUserRecord "webhook-checkout-owner@example.com" "staff" True
                let sessionId = "cs_webhook_attempt_123"
                _ <-
                    newRecord @BillingCheckoutAttempt
                        |> set #venueId (unpackId venue.id)
                        |> set #initiatedByUserId (unpackId owner.id)
                        |> set #livemode False
                        |> set #stripeCustomerId "cus_webhook_attempt_123"
                        |> set #stripePriceId "price_monthly_123"
                        |> set #stripeCheckoutSessionId (Just sessionId)
                        |> createRecord

                Right _ <- handleStripeWebhookPayload StripeTestMode (checkoutSessionEventForAttempt "evt_checkout_attempt_completed" venue sessionId "cus_webhook_attempt_123" "sub_webhook_attempt_123")

                attempt <- query @BillingCheckoutAttempt |> filterWhere (#stripeCheckoutSessionId, Just sessionId) |> fetchOne
                attempt.status `shouldBe` "completed"
                attempt.stripeSubscriptionId `shouldBe` Just "sub_webhook_attempt_123"
                attempt.completedAt `shouldSatisfy` isJust

        it "does not let an older Checkout event regress a newer attempt state" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Ordered Checkout Venue"
                owner <- createUserRecord "webhook-ordered-checkout-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                let sessionId = "cs_ordered_checkout_123"
                _ <-
                    newRecord @BillingCheckoutAttempt
                        |> set #venueId (unpackId venue.id)
                        |> set #initiatedByUserId (unpackId owner.id)
                        |> set #livemode False
                        |> set #stripeCustomerId "cus_ordered_checkout_123"
                        |> set #stripePriceId "price_monthly_123"
                        |> set #stripeCheckoutSessionId (Just sessionId)
                        |> createRecord
                let newerEvent = checkoutSessionEventForAttemptAt (testStripeEventCreatedSeconds + 1) "checkout.session.async_payment_succeeded" "evt_ordered_checkout_newer" venue sessionId "cus_ordered_checkout_123" "sub_ordered_checkout_123"
                let olderEvent = checkoutSessionEventForAttemptAt testStripeEventCreatedSeconds "checkout.session.async_payment_failed" "evt_ordered_checkout_older" venue sessionId "cus_ordered_checkout_123" "sub_ordered_checkout_123"

                Right _ <- handleStripeWebhookPayload StripeTestMode newerEvent
                Right _ <- handleStripeWebhookPayload StripeTestMode olderEvent

                attempt <- query @BillingCheckoutAttempt |> filterWhere (#stripeCheckoutSessionId, Just sessionId) |> fetchOne
                attempt.status `shouldBe` "completed"
                attempt.errorCode `shouldBe` Nothing
                notificationCount <- query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetchCount
                notificationCount `shouldBe` 0

        it "rolls back a failed supported event and applies its later retry once" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Atomic Retry Venue"
                customer <- createBillingCustomer venue "cus_atomic_before_retry"
                let eventBody = checkoutSessionEventForAttempt "evt_atomic_retry_123" venue "cs_atomic_retry_123" "cus_atomic_after_retry" "sub_atomic_retry_123"
                signatureHeader <- signedStripeHeader testStripeConfig.webhookSecret eventBody

                failedResponse <- withStripeConfigForTest (Right testStripeConfig) do
                    callStripeWebhookWithJsonBody eventBody signatureHeader

                failedResponse `responseStatusShouldBe` status500
                failedEventCount <- query @BillingEvent |> fetchCount
                failedEventCount `shouldBe` 0
                failedSubscriptionCount <- query @VenueSubscription |> fetchCount
                failedSubscriptionCount `shouldBe` 0

                _ <- customer |> set #stripeCustomerId "cus_atomic_after_retry" |> updateRecord
                retryResponse <- withStripeConfigForTest (Right testStripeConfig) do
                    callStripeWebhookWithJsonBody eventBody signatureHeader

                retryResponse `responseStatusShouldBe` status200
                eventCount <- query @BillingEvent |> filterWhere (#stripeEventId, "evt_atomic_retry_123" :: Text) |> fetchCount
                eventCount `shouldBe` 1

        it "persists live provider mode on subscription snapshots" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Live Subscription Mode Venue"
                _ <-
                    newRecord @VenueBillingCustomer
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeCustomerId "cus_live_subscription_mode"
                        |> set #livemode True
                        |> createRecord

                Right result <- handleStripeWebhookPayload StripeLiveMode (subscriptionEventWithLivemode True "evt_live_subscription_mode" venue "cus_live_subscription_mode" "sub_live_subscription_mode" "active")

                result `shouldSatisfy` isProcessed
                event <- query @BillingEvent |> filterWhere (#stripeEventId, "evt_live_subscription_mode" :: Text) |> fetchOne
                event.livemode `shouldBe` True
                subscription <- query @VenueSubscription |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                subscription.livemode `shouldBe` True

        it "fails closed when persisted Subscription mode differs from the validated event" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Persisted Mode Mismatch Venue"
                _ <- createBillingCustomer venue "cus_persisted_mode_mismatch"
                subscription <-
                    newRecord @VenueSubscription
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeSubscriptionId "sub_persisted_mode_mismatch"
                        |> set #stripePriceId "price_monthly_123"
                        |> set #livemode True
                        |> set #status "active"
                        |> createRecord

                result <- try (handleStripeWebhookPayload StripeTestMode (subscriptionEvent "evt_persisted_mode_mismatch" venue "cus_persisted_mode_mismatch" "sub_persisted_mode_mismatch" "past_due"))
                    :: IO (Either SomeException (Either Text BillingWebhookResult))

                result `shouldSatisfy` \case
                    Left _  -> True
                    Right _ -> False
                retainedSubscription <- fetch subscription.id
                retainedSubscription.livemode `shouldBe` True
                retainedSubscription.status `shouldBe` "active"
                query @BillingEvent |> fetchCount `shouldReturn` 0
                query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetchCount `shouldReturn` 0

        it "fails closed when an invoice resolves through a Customer from the opposite mode" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Invoice Customer Mode Mismatch Venue"
                _ <-
                    newRecord @VenueBillingCustomer
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeCustomerId "cus_invoice_mode_mismatch"
                        |> set #livemode True
                        |> createRecord

                result <- try (handleStripeWebhookPayload StripeTestMode (invoicePaymentFailedEvent "evt_invoice_mode_mismatch" "cus_invoice_mode_mismatch" "sub_invoice_mode_mismatch"))
                    :: IO (Either SomeException (Either Text BillingWebhookResult))

                result `shouldSatisfy` \case
                    Left _  -> True
                    Right _ -> False
                query @BillingEvent |> fetchCount `shouldReturn` 0
                query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetchCount `shouldReturn` 0

        it "persists live provider mode on webhook-created Customer associations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Live Customer Mode Venue"

                Right result <- handleStripeWebhookPayload StripeLiveMode (checkoutSessionEventForVenue True "evt_live_customer_mode" venue "cus_live_customer_mode" "sub_live_customer_mode")

                result `shouldSatisfy` isProcessed
                customer <- query @VenueBillingCustomer |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                customer.stripeCustomerId `shouldBe` "cus_live_customer_mode"
                customer.livemode `shouldBe` True
                customer.createdByUserId `shouldBe` Nothing

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

        it "normalizes a Stripe Portal cancel_at at the current period end as scheduled cancellation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Dahlia Portal Cancellation Venue"
                owner <- createUserRecord "dahlia-portal-cancellation-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createBillingCustomer venue "cus_dahlia_cancel_at_123"
                Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventOfTypeWithCancellationAt "customer.subscription.created" testStripeEventCreatedSeconds False "evt_subscription_cancel_at_initial_dahlia" venue "cus_dahlia_cancel_at_123" "sub_dahlia_cancel_at_123" "active")
                eventBody <- LByteString.readFile "Test/Fixtures/stripe/2026-06-24.dahlia/webhook-subscription-cancel-at-updated.json"
                signatureHeader <- signedStripeHeader testStripeConfig.webhookSecret eventBody

                response <- withStripeConfigForTest (Right testStripeConfig) do
                    callStripeWebhookWithJsonBody eventBody signatureHeader

                response `responseStatusShouldBe` status200
                subscription <- query @VenueSubscription |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                subscription.status `shouldBe` "active"
                subscription.currentPeriodEnd `shouldBe` Just (posixSecondsToUTCTime 1787356800)
                subscription.cancelAtPeriodEnd `shouldBe` True
                [notificationJob] <- query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetch
                notificationJob.dedupeKey `shouldSatisfy` maybe False (Text.isInfixOf ":cancellation_scheduled:")

        it "processes reviewed Dahlia created, updated, deleted, failed-payment, and duplicate fixtures" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Dahlia Lifecycle Venue"
                _ <- createBillingCustomer venue "cus_dahlia_123"

                forM_
                    [ ("webhook-subscription-created.json", "active")
                    , ("webhook-subscription-updated.json", "active")
                    , ("webhook-subscription-deleted.json", "canceled")
                    ]
                    \(fixtureName, expectedStatus) -> do
                        eventBody <- LByteString.readFile ("Test/Fixtures/stripe/2026-06-24.dahlia/" <> fixtureName)
                        signatureHeader <- signedStripeHeader testStripeConfig.webhookSecret eventBody

                        response <- withStripeConfigForTest (Right testStripeConfig) do
                            callStripeWebhookWithJsonBody eventBody signatureHeader

                        response `responseStatusShouldBe` status200
                        subscription <- query @VenueSubscription |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                        subscription.status `shouldBe` expectedStatus

                query @BillingEvent |> filterWhere (#providerObjectId, Just ("sub_dahlia_123" :: Text)) |> fetchCount `shouldReturn` 3

                failedPaymentBody <- LByteString.readFile "Test/Fixtures/stripe/2026-06-24.dahlia/webhook-invoice-payment-failed.json"
                failedPaymentSignature <- signedStripeHeader testStripeConfig.webhookSecret failedPaymentBody
                failedPaymentResponse <- withStripeConfigForTest (Right testStripeConfig) do
                    callStripeWebhookWithJsonBody failedPaymentBody failedPaymentSignature

                failedPaymentResponse `responseStatusShouldBe` status200
                failedPaymentEvent <- query @BillingEvent |> filterWhere (#stripeEventId, "evt_invoice_payment_failed_dahlia" :: Text) |> fetchOne
                failedPaymentEvent.eventType `shouldBe` "invoice.payment_failed"
                failedPaymentEvent.providerObjectType `shouldBe` Just "invoice"
                failedPaymentEvent.stripeSubscriptionId `shouldBe` Just "sub_dahlia_123"
                failedPaymentEvent.status `shouldBe` "processed"

                duplicateFailedPaymentResponse <- withStripeConfigForTest (Right testStripeConfig) do
                    callStripeWebhookWithJsonBody failedPaymentBody failedPaymentSignature
                duplicateFailedPaymentResponse `responseStatusShouldBe` status200
                query @BillingEvent |> filterWhere (#stripeEventId, "evt_invoice_payment_failed_dahlia" :: Text) |> fetchCount `shouldReturn` 1

        it "deduplicates already processed Stripe event ids" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Duplicate Venue"
                _ <- createBillingCustomer venue "cus_duplicate_123"
                let eventBody = subscriptionEvent "evt_duplicate_subscription" venue "cus_duplicate_123" "sub_duplicate" "active"

                Right firstResult <- handleStripeWebhookPayload StripeTestMode eventBody
                Right secondResult <- handleStripeWebhookPayload StripeTestMode eventBody

                firstResult `shouldSatisfy` isProcessed
                secondResult `shouldSatisfy` isDuplicate
                eventCount <- query @BillingEvent |> filterWhere (#stripeEventId, "evt_duplicate_subscription" :: Text) |> fetchCount
                eventCount `shouldBe` 1

        it "serializes concurrent duplicate deliveries into one processed event" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Concurrent Duplicate Venue"
                _ <- createBillingCustomer venue "cus_concurrent_duplicate_123"
                let eventBody = subscriptionEvent "evt_concurrent_duplicate" venue "cus_concurrent_duplicate_123" "sub_concurrent_duplicate" "active"
                firstResult <- newEmptyMVar
                secondResult <- newEmptyMVar

                runWebhookInThread eventBody firstResult
                runWebhookInThread eventBody secondResult
                firstDelivery <- takeMVar firstResult
                secondDelivery <- takeMVar secondResult
                let deliveries = [firstDelivery, secondDelivery]
                deliveries `shouldSatisfy` all isSuccessfulWebhookDelivery
                let webhookResults = [result | Right (Right result) <- deliveries]
                length (filter isProcessed webhookResults) `shouldBe` 1
                length (filter isDuplicate webhookResults) `shouldBe` 1
                eventCount <- query @BillingEvent |> filterWhere (#stripeEventId, "evt_concurrent_duplicate" :: Text) |> fetchCount
                eventCount `shouldBe` 1
                subscriptionCount <- query @VenueSubscription |> fetchCount
                subscriptionCount `shouldBe` 1

        it "records unknown events as ignored without storing raw payloads" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Ignored Venue"

                Right result <- handleStripeWebhookPayload StripeTestMode (unknownEvent "evt_unknown_123" venue)

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
                inactiveOwner <- createUserRecord "billing-inactive-owner@example.com" "staff" True
                inactiveMembership <- createVenueMembershipRecord venue inactiveOwner "venue_owner"
                _ <- inactiveMembership |> set #isActive False |> updateRecord
                deactivatedOwner <- createUserRecord "billing-deactivated-at-enqueue-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue deactivatedOwner "venue_owner"
                now <- getCurrentTime
                _ <- deactivatedOwner |> set #deactivatedAt (Just now) |> updateRecord
                _ <- createUserRecordWithPlatformRole "billing-problem-support@example.com" "staff" (Just SuperAdminRole) True
                _ <- createBillingCustomer venue "cus_payment_failed_123"
                let eventBody = invoicePaymentFailedEvent "evt_invoice_failed_123" "cus_payment_failed_123" "sub_failed_123"

                Right result <- handleStripeWebhookPayload StripeTestMode eventBody
                Right duplicateResult <- handleStripeWebhookPayload StripeTestMode eventBody

                result `shouldSatisfy` isProcessed
                duplicateResult `shouldSatisfy` isDuplicate
                jobs <- query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetch
                length jobs `shouldBe` 2
                map (.venueId) jobs `shouldBe` [Just (unpackId venue.id), Just (unpackId venue.id)]
                map (.relatedTable) jobs `shouldBe` [Just "billing_events", Just "billing_events"]

        it "deduplicates same-period trouble after every terminal notification job state" $ withContext do
            forM_ [JobStatusSucceeded, JobStatusFailed, JobStatusTimedOut] \terminalStatus ->
                withCleanDb do
                    venue <- createVenueWithConfig "Webhook Trouble Dedupe Venue"
                    owner <- createUserRecord "billing-trouble-dedupe-owner@example.com" "staff" True
                    _ <- createVenueMembershipRecord venue owner "venue_owner"
                    _ <- createBillingCustomer venue "cus_trouble_dedupe_123"
                    Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventAt testStripeEventCreatedSeconds "evt_trouble_active" venue "cus_trouble_dedupe_123" "sub_trouble_dedupe_123" "active")

                    Right _ <- handleStripeWebhookPayload StripeTestMode (invoicePaymentFailedEventForPeriodAt (testStripeEventCreatedSeconds + 1) 1762592000 1765184000 "evt_trouble_invoice" "cus_trouble_dedupe_123" "sub_trouble_dedupe_123")
                    firstJob <- query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetchOne
                    case terminalStatus of
                        JobStatusSucceeded ->
                            withFrameworkConfig config \frameworkConfig -> do
                                let ?context = frameworkConfig
                                performBillingNotificationJob firstJob
                        _ -> do
                            _ <- firstJob |> set #status terminalStatus |> updateRecord
                            pure ()
                    terminalFirstJob <- fetch firstJob.id
                    terminalFirstJob.status `shouldBe` terminalStatus

                    Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventAt (testStripeEventCreatedSeconds + 2) "evt_trouble_past_due" venue "cus_trouble_dedupe_123" "sub_trouble_dedupe_123" "past_due")

                    jobs <- query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetch
                    length jobs `shouldBe` 1
                    map (.relatedTable) jobs `shouldBe` [Just "billing_events"]
                    map (.dedupeKey) jobs `shouldSatisfy` all (maybe False (Text.isInfixOf ":payment_trouble:"))

        it "deduplicates a trouble transition against its adjacent renewal invoice period" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Renewal Boundary Dedupe Venue"
                owner <- createUserRecord "billing-renewal-boundary-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createBillingCustomer venue "cus_renewal_boundary_123"
                Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventAt testStripeEventCreatedSeconds "evt_boundary_active" venue "cus_renewal_boundary_123" "sub_renewal_boundary_123" "active")
                Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventAt (testStripeEventCreatedSeconds + 1) "evt_boundary_trouble" venue "cus_renewal_boundary_123" "sub_renewal_boundary_123" "past_due")

                Right _ <- handleStripeWebhookPayload StripeTestMode (invoicePaymentFailedEventForPeriodAt (testStripeEventCreatedSeconds + 2) 1762592000 1765184000 "evt_boundary_invoice" "cus_renewal_boundary_123" "sub_renewal_boundary_123")

                jobs <- query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetch
                length jobs `shouldBe` 1
                map (.dedupeKey) jobs `shouldSatisfy` all (maybe False (Text.isInfixOf ":payment_trouble:"))

        it "deduplicates invoice-first delivery when the trouble snapshot has advanced periods" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Invoice First Boundary Venue"
                owner <- createUserRecord "billing-invoice-first-boundary-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createBillingCustomer venue "cus_invoice_first_boundary_123"
                Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventAt testStripeEventCreatedSeconds "evt_invoice_first_active" venue "cus_invoice_first_boundary_123" "sub_invoice_first_boundary_123" "active")
                Right _ <- handleStripeWebhookPayload StripeTestMode (invoicePaymentFailedEventForPeriodAt (testStripeEventCreatedSeconds + 1) 1762592000 1765184000 "evt_invoice_first_failed" "cus_invoice_first_boundary_123" "sub_invoice_first_boundary_123")

                Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventWithModesAndCancellationForPeriodAt False False "customer.subscription.updated" (testStripeEventCreatedSeconds + 2) 1762592000 1765184000 False "evt_invoice_first_trouble" venue "cus_invoice_first_boundary_123" "sub_invoice_first_boundary_123" "past_due")

                jobs <- query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetch
                length jobs `shouldBe` 1
                map (.dedupeKey) jobs `shouldSatisfy` all (maybe False (Text.isInfixOf ":payment_trouble:"))

        it "notifies again when a later billing period fails while the subscription remains troubled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Later Trouble Period Venue"
                owner <- createUserRecord "billing-later-period-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createBillingCustomer venue "cus_later_trouble_period_123"
                Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventAt testStripeEventCreatedSeconds "evt_later_period_active" venue "cus_later_trouble_period_123" "sub_later_trouble_period_123" "active")
                Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventAt (testStripeEventCreatedSeconds + 1) "evt_later_period_trouble" venue "cus_later_trouble_period_123" "sub_later_trouble_period_123" "past_due")

                Right _ <- handleStripeWebhookPayload StripeTestMode (invoicePaymentFailedEventForPeriodAt (testStripeEventCreatedSeconds + 2) 1765184000 1767776000 "evt_later_period_invoice" "cus_later_trouble_period_123" "sub_later_trouble_period_123")

                jobs <- query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetch
                length jobs `shouldBe` 2
                let dedupeKeys = mapMaybe (.dedupeKey) jobs
                length (nub dedupeKeys) `shouldBe` 2
                dedupeKeys `shouldSatisfy` all (Text.isInfixOf ":payment_trouble:")

        it "skips queued owner mail when membership or account eligibility changes before delivery" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Notification Reauthorization Venue"
                deactivatedOwner <- createUserRecord "billing-deactivated-owner@example.com" "staff" True
                deactivatedMembership <- createVenueMembershipRecord venue deactivatedOwner "venue_owner"
                archivedOwner <- createUserRecord "billing-archived-owner@example.com" "staff" True
                archivedMembership <- createVenueMembershipRecord venue archivedOwner "venue_owner"
                accountDeactivatedOwner <- createUserRecord "billing-account-deactivated-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue accountDeactivatedOwner "venue_owner"
                _ <- createBillingCustomer venue "cus_notification_reauthorization_123"

                Right _ <- handleStripeWebhookPayload StripeTestMode (invoicePaymentFailedEvent "evt_notification_reauthorization" "cus_notification_reauthorization_123" "sub_notification_reauthorization_123")
                jobs <- query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetch
                length jobs `shouldBe` 3

                now <- getCurrentTime
                _ <- deactivatedMembership |> set #isActive False |> updateRecord
                _ <- archivedMembership |> set #archivedAt (Just now) |> updateRecord
                _ <- accountDeactivatedOwner |> set #deactivatedAt (Just now) |> updateRecord
                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    forM_ jobs performBillingNotificationJob

                completedJobs <- query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetch
                map (.status) completedJobs `shouldBe` [JobStatusSucceeded, JobStatusSucceeded, JobStatusSucceeded]
                map (.result) completedJobs `shouldSatisfy` all (Text.isInfixOf "skipped_ineligible_recipient" . cs . Aeson.encode)

        it "does not notify from an initial active snapshot already marked for cancellation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Initial Cancellation Snapshot Venue"
                owner <- createUserRecord "billing-initial-cancellation-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createBillingCustomer venue "cus_initial_cancellation_snapshot_123"

                Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventOfTypeWithCancellationAt "customer.subscription.created" testStripeEventCreatedSeconds True "evt_initial_cancellation_snapshot" venue "cus_initial_cancellation_snapshot_123" "sub_initial_cancellation_snapshot_123" "active")

                query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetchCount `shouldReturn` 0

        it "notifies when a non-terminal subscription resumes renewal" $ withContext do
            forM_ ["trialing", "past_due"] \status ->
                withCleanDb do
                    venue <- createVenueWithConfig ("Webhook Renewal Resumed " <> status <> " Venue")
                    owner <- createUserRecord ("billing-renewal-resumed-" <> status <> "-owner@example.com") "staff" True
                    _ <- createVenueMembershipRecord venue owner "venue_owner"
                    _ <- createBillingCustomer venue "cus_renewal_resumed_123"

                    Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventOfTypeWithCancellationAt "customer.subscription.created" testStripeEventCreatedSeconds True "evt_cancel_scheduled" venue "cus_renewal_resumed_123" "sub_renewal_resumed_123" status)
                    Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventWithCancellationAt (testStripeEventCreatedSeconds + 1) False "evt_renewal_resumed" venue "cus_renewal_resumed_123" "sub_renewal_resumed_123" status)

                    notificationJobs <- query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetch
                    let renewalJobs = filter (maybe False (Text.isInfixOf ":renewal_resumed:") . (.dedupeKey)) notificationJobs
                    length renewalJobs `shouldBe` 1

        it "keeps trouble, recovery, scheduled cancellation, resumed renewal, and completed cancellation independently visible" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Notification Transitions Venue"
                owner <- createUserRecord "billing-transitions-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createBillingCustomer venue "cus_notification_transitions_123"

                Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventOfTypeWithCancellationAt "customer.subscription.created" testStripeEventCreatedSeconds False "evt_transition_initial_active" venue "cus_notification_transitions_123" "sub_notification_transitions_123" "active")
                Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventAt (testStripeEventCreatedSeconds + 1) "evt_transition_trouble" venue "cus_notification_transitions_123" "sub_notification_transitions_123" "past_due")
                Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventAt (testStripeEventCreatedSeconds + 2) "evt_transition_recovered" venue "cus_notification_transitions_123" "sub_notification_transitions_123" "active")
                Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventWithCancellationAt (testStripeEventCreatedSeconds + 3) True "evt_transition_cancel_scheduled" venue "cus_notification_transitions_123" "sub_notification_transitions_123" "active")
                Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventWithCancellationAt (testStripeEventCreatedSeconds + 4) False "evt_transition_renewal_resumed" venue "cus_notification_transitions_123" "sub_notification_transitions_123" "active")
                Right _ <- handleStripeWebhookPayload StripeTestMode (subscriptionEventOfTypeWithCancellationAt "customer.subscription.deleted" (testStripeEventCreatedSeconds + 5) False "evt_transition_canceled" venue "cus_notification_transitions_123" "sub_notification_transitions_123" "canceled")

                jobs <- query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> orderByAsc #createdAt |> fetch
                length jobs `shouldBe` 5
                let dedupeKeys = mapMaybe (.dedupeKey) jobs
                dedupeKeys `shouldSatisfy` any (Text.isInfixOf ":payment_trouble:")
                dedupeKeys `shouldSatisfy` any (Text.isInfixOf ":payment_recovered:")
                dedupeKeys `shouldSatisfy` any (Text.isInfixOf ":cancellation_scheduled:")
                dedupeKeys `shouldSatisfy` any (Text.isInfixOf ":renewal_resumed:")
                dedupeKeys `shouldSatisfy` any (Text.isInfixOf ":cancellation_completed:")

        it "notifies support once only after a billing operation exhausts retries" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Terminal Failure Venue"
                owner <- createUserRecord "billing-terminal-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                supportUser <- createUserRecordWithPlatformRole "billing-terminal-support@example.com" "staff" (Just SuperAdminRole) True
                deactivatedSupportUser <- createUserRecordWithPlatformRole "billing-terminal-deactivated-support@example.com" "staff" (Just SuperAdminRole) True
                now <- getCurrentTime
                _ <- deactivatedSupportUser |> set #deactivatedAt (Just now) |> updateRecord
                sourceJob <-
                    newRecord @AppJob
                        |> set #jobKind "billing_reconciliation"
                        |> set #venueId (Just (unpackId venue.id))
                        |> set #status JobStatusRunning
                        |> set #attemptsCount (appJobMaxAttempts - 1)
                        |> set #lastError (Just "pm_secret billing@example.test 4111111111111111")
                        |> createRecord

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    _ <- try (dispatchAppJob sourceJob) :: IO (Either SomeException ())
                    query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetchCount `shouldReturn` 0

                    finalAttempt <- sourceJob |> set #attemptsCount appJobMaxAttempts |> updateRecord
                    _ <- try (dispatchAppJob finalAttempt) :: IO (Either SomeException ())
                    _ <- try (dispatchAppJob finalAttempt) :: IO (Either SomeException ())
                    pure ()

                jobs <- query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetch
                length jobs `shouldBe` 1
                map (.relatedTable) jobs `shouldBe` [Just "app_jobs"]
                map (.relatedId) jobs `shouldBe` [Just (unpackId sourceJob.id)]
                map (.payload) jobs `shouldSatisfy` all (not . Text.isInfixOf "pm_secret" . cs . Aeson.encode)
                map (.payload) jobs `shouldSatisfy` all (Text.isInfixOf (inputValue supportUser.id) . cs . Aeson.encode)
                map (.payload) jobs `shouldSatisfy` all (not . Text.isInfixOf (inputValue deactivatedSupportUser.id) . cs . Aeson.encode)

                _ <- supportUser |> set #deactivatedAt (Just now) |> updateRecord
                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    forM_ jobs performBillingNotificationJob
                completedSupportJob <- query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetchOne
                completedSupportJob.status `shouldBe` JobStatusSucceeded
                cs (Aeson.encode completedSupportJob.result) `shouldSatisfy` Text.isInfixOf "skipped_ineligible_recipient"

        it "accepts a valid signed webhook while new Checkout is disabled" $ withContext do
            withCleanDb do
                let eventBody = checkoutSessionEventWithoutVenue "evt_controller_checkout_123" "cus_controller_123" "sub_controller_123"
                signatureHeader <- signedStripeHeader testStripeConfig.webhookSecret eventBody
                let checkoutDisabledConfig =
                        testStripeConfig
                            { stripeDeploymentControls =
                                testStripeConfig.stripeDeploymentControls
                                    { stripeCheckoutEnabled = False
                                    }
                            }
                response <- withStripeConfigForTest (Right checkoutDisabledConfig) do
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

        it "rejects test-mode webhook events in a live-mode integration" $ withContext do
            withCleanDb do
                let eventBody = checkoutSessionEventWithoutVenue "evt_wrong_provider_mode" "cus_wrong_mode_123" "sub_wrong_mode_123"
                signatureHeader <- signedStripeHeader testStripeConfig.webhookSecret eventBody
                let liveConfig = testStripeConfig { stripeMode = StripeLiveMode, appBaseUrl = "https://billing.example.test" }

                response <- withStripeConfigForTest (Right liveConfig) do
                    callStripeWebhookWithJsonBody eventBody signatureHeader

                response `responseStatusShouldBe` status400
                eventCount <- query @BillingEvent |> fetchCount
                eventCount `shouldBe` 0

        it "rejects a webhook Subscription Item Price from the opposite Stripe mode" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Webhook Nested Price Mode Venue"
                let eventBody = subscriptionEventWithPriceLivemode True "evt_nested_price_mode" venue "cus_nested_price_mode" "sub_nested_price_mode" "active"
                signatureHeader <- signedStripeHeader testStripeConfig.webhookSecret eventBody

                response <- withStripeConfigForTest (Right testStripeConfig) do
                    callStripeWebhookWithJsonBody eventBody signatureHeader

                response `responseStatusShouldBe` status400
                eventCount <- query @BillingEvent |> fetchCount
                eventCount `shouldBe` 0
                subscriptionCount <- query @VenueSubscription |> fetchCount
                subscriptionCount `shouldBe` 0

        it "rejects signed webhook snapshots with no explicit Stripe mode" $ withContext do
            withCleanDb do
                let eventBody = checkoutSessionEventWithoutSnapshotLivemode "evt_missing_snapshot_mode" "cus_missing_snapshot_mode" "sub_missing_snapshot_mode"
                signatureHeader <- signedStripeHeader testStripeConfig.webhookSecret eventBody

                response <- withStripeConfigForTest (Right testStripeConfig) do
                    callStripeWebhookWithJsonBody eventBody signatureHeader

                response `responseStatusShouldBe` status400
                eventCount <- query @BillingEvent |> fetchCount
                eventCount `shouldBe` 0

        it "rejects wrong Stripe Event and supported snapshot object discriminators" $ withContext do
            withCleanDb do
                let wrongEventObject = checkoutSessionEventWithObjectTypes "customer" "checkout.session" "evt_wrong_event_object"
                eventSignature <- signedStripeHeader testStripeConfig.webhookSecret wrongEventObject
                eventResponse <- withStripeConfigForTest (Right testStripeConfig) do
                    callStripeWebhookWithJsonBody wrongEventObject eventSignature

                let wrongSnapshotObject = checkoutSessionEventWithObjectTypes "event" "customer" "evt_wrong_snapshot_object"
                snapshotSignature <- signedStripeHeader testStripeConfig.webhookSecret wrongSnapshotObject
                snapshotResponse <- withStripeConfigForTest (Right testStripeConfig) do
                    callStripeWebhookWithJsonBody wrongSnapshotObject snapshotSignature

                eventResponse `responseStatusShouldBe` status400
                snapshotResponse `responseStatusShouldBe` status400
                eventCount <- query @BillingEvent |> fetchCount
                eventCount `shouldBe` 0

        it "rejects signed webhook events with no explicit Stripe mode" $ withContext do
            withCleanDb do
                let eventBody = checkoutSessionEventWithoutLivemode "evt_missing_provider_mode" "cus_missing_mode_123" "sub_missing_mode_123"
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
        |> set #livemode False
        |> createRecord

subscriptionEvent :: Text -> Venue -> Text -> Text -> Text -> LByteString.ByteString
subscriptionEvent = subscriptionEventWithModes False False

subscriptionEventAt :: Integer -> Text -> Venue -> Text -> Text -> Text -> LByteString.ByteString
subscriptionEventAt = subscriptionEventWithModesAt False False

subscriptionEventWithLivemode :: Bool -> Text -> Venue -> Text -> Text -> Text -> LByteString.ByteString
subscriptionEventWithLivemode livemode = subscriptionEventWithModes livemode livemode

subscriptionEventWithPriceLivemode :: Bool -> Text -> Venue -> Text -> Text -> Text -> LByteString.ByteString
subscriptionEventWithPriceLivemode = subscriptionEventWithModes False

subscriptionEventWithModes :: Bool -> Bool -> Text -> Venue -> Text -> Text -> Text -> LByteString.ByteString
subscriptionEventWithModes livemode priceLivemode = subscriptionEventWithModesAt livemode priceLivemode testStripeEventCreatedSeconds

subscriptionEventWithModesAt :: Bool -> Bool -> Integer -> Text -> Venue -> Text -> Text -> Text -> LByteString.ByteString
subscriptionEventWithModesAt livemode priceLivemode eventCreatedAt =
    subscriptionEventWithModesAndCancellationAt livemode priceLivemode "customer.subscription.updated" eventCreatedAt False

subscriptionEventWithCancellationAt :: Integer -> Bool -> Text -> Venue -> Text -> Text -> Text -> LByteString.ByteString
subscriptionEventWithCancellationAt =
    subscriptionEventOfTypeWithCancellationAt "customer.subscription.updated"

subscriptionEventOfTypeWithCancellationAt :: Text -> Integer -> Bool -> Text -> Venue -> Text -> Text -> Text -> LByteString.ByteString
subscriptionEventOfTypeWithCancellationAt =
    subscriptionEventWithModesAndCancellationAt False False

subscriptionEventWithModesAndCancellationAt :: Bool -> Bool -> Text -> Integer -> Bool -> Text -> Venue -> Text -> Text -> Text -> LByteString.ByteString
subscriptionEventWithModesAndCancellationAt livemode priceLivemode eventType eventCreatedAt =
    subscriptionEventWithModesAndCancellationForPeriodAt livemode priceLivemode eventType eventCreatedAt 1760000000 1762592000

subscriptionEventWithModesAndCancellationForPeriodAt :: Bool -> Bool -> Text -> Integer -> Integer -> Integer -> Bool -> Text -> Venue -> Text -> Text -> Text -> LByteString.ByteString
subscriptionEventWithModesAndCancellationForPeriodAt livemode priceLivemode eventType eventCreatedAt periodStart periodEnd cancelAtPeriodEnd eventId venue customerId subscriptionId status =
    Aeson.encode $
        Aeson.object
            [ "id" Aeson..= eventId
            , "object" Aeson..= ("event" :: Text)
            , "created" Aeson..= eventCreatedAt
            , "type" Aeson..= eventType
            , "livemode" Aeson..= livemode
            , "api_version" Aeson..= pinnedStripeApiVersion
            , "data" Aeson..=
                Aeson.object
                    [ "object" Aeson..=
                        Aeson.object
                            [ "object" Aeson..= ("subscription" :: Text)
                            , "id" Aeson..= subscriptionId
                            , "customer" Aeson..= customerId
                            , "livemode" Aeson..= livemode
                            , "status" Aeson..= status
                            , "cancel_at_period_end" Aeson..= cancelAtPeriodEnd
                            , "metadata" Aeson..= Aeson.object ["venue_id" Aeson..= inputValue venue.id]
                            , "items" Aeson..=
                                Aeson.object
                                    [ "object" Aeson..= ("list" :: Text)
                                    , "data" Aeson..=
                                        [ Aeson.object
                                            [ "object" Aeson..= ("subscription_item" :: Text)
                                            , "current_period_start" Aeson..= periodStart
                                            , "current_period_end" Aeson..= periodEnd
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
            , "object" Aeson..= ("price" :: Text)
            , "active" Aeson..= True
            , "currency" Aeson..= ("aud" :: Text)
            , "livemode" Aeson..= priceLivemode
            , "unit_amount" Aeson..= (10000 :: Int)
            , "type" Aeson..= ("recurring" :: Text)
            , "recurring" Aeson..=
                Aeson.object
                    [ "interval" Aeson..= ("month" :: Text)
                    , "interval_count" Aeson..= (1 :: Int)
                    , "usage_type" Aeson..= ("licensed" :: Text)
                    ]
            ]

checkoutSessionEventForVenue :: Bool -> Text -> Venue -> Text -> Text -> LByteString.ByteString
checkoutSessionEventForVenue livemode eventId venue customerId subscriptionId =
    checkoutSessionEventWithId testStripeEventCreatedSeconds "checkout.session.completed" livemode eventId venue "cs_live_customer_mode" customerId subscriptionId

checkoutSessionEventForAttempt :: Text -> Venue -> Text -> Text -> Text -> LByteString.ByteString
checkoutSessionEventForAttempt = checkoutSessionEventForAttemptAt testStripeEventCreatedSeconds "checkout.session.completed"

checkoutSessionEventForAttemptAt :: Integer -> Text -> Text -> Venue -> Text -> Text -> Text -> LByteString.ByteString
checkoutSessionEventForAttemptAt eventCreatedAt eventType eventId venue sessionId customerId subscriptionId =
    checkoutSessionEventWithId eventCreatedAt eventType False eventId venue sessionId customerId subscriptionId

checkoutSessionEventWithId :: Integer -> Text -> Bool -> Text -> Venue -> Text -> Text -> Text -> LByteString.ByteString
checkoutSessionEventWithId eventCreatedAt eventType livemode eventId venue sessionId customerId subscriptionId =
    Aeson.encode $
        Aeson.object
            [ "id" Aeson..= eventId
            , "object" Aeson..= ("event" :: Text)
            , "created" Aeson..= eventCreatedAt
            , "type" Aeson..= eventType
            , "livemode" Aeson..= livemode
            , "api_version" Aeson..= pinnedStripeApiVersion
            , "data" Aeson..=
                Aeson.object
                    [ "object" Aeson..=
                        Aeson.object
                            [ "object" Aeson..= ("checkout.session" :: Text)
                            , "id" Aeson..= sessionId
                            , "livemode" Aeson..= livemode
                            , "customer" Aeson..= customerId
                            , "subscription" Aeson..= subscriptionId
                            , "client_reference_id" Aeson..= inputValue venue.id
                            , "metadata" Aeson..= Aeson.object ["venue_id" Aeson..= inputValue venue.id]
                            , "status" Aeson..= ("complete" :: Text)
                            ]
                    ]
            ]

checkoutSessionEventWithoutVenue :: Text -> Text -> Text -> LByteString.ByteString
checkoutSessionEventWithoutVenue = checkoutSessionEventWithApiVersion pinnedStripeApiVersion

checkoutSessionEventWithApiVersion :: Text -> Text -> Text -> Text -> LByteString.ByteString
checkoutSessionEventWithApiVersion apiVersion eventId customerId subscriptionId =
    Aeson.encode $
        Aeson.object
            [ "id" Aeson..= eventId
            , "object" Aeson..= ("event" :: Text)
            , "created" Aeson..= testStripeEventCreatedSeconds
            , "type" Aeson..= ("checkout.session.completed" :: Text)
            , "livemode" Aeson..= False
            , "api_version" Aeson..= apiVersion
            , "data" Aeson..=
                Aeson.object
                    [ "object" Aeson..=
                        Aeson.object
                            [ "object" Aeson..= ("checkout.session" :: Text)
                            , "id" Aeson..= ("cs_controller_123" :: Text)
                            , "livemode" Aeson..= False
                            , "customer" Aeson..= customerId
                            , "subscription" Aeson..= subscriptionId
                            , "status" Aeson..= ("complete" :: Text)
                            ]
                    ]
            ]

checkoutSessionEventWithoutSnapshotLivemode :: Text -> Text -> Text -> LByteString.ByteString
checkoutSessionEventWithoutSnapshotLivemode eventId customerId subscriptionId =
    Aeson.encode $
        Aeson.object
            [ "id" Aeson..= eventId
            , "object" Aeson..= ("event" :: Text)
            , "created" Aeson..= testStripeEventCreatedSeconds
            , "type" Aeson..= ("checkout.session.completed" :: Text)
            , "livemode" Aeson..= False
            , "api_version" Aeson..= pinnedStripeApiVersion
            , "data" Aeson..=
                Aeson.object
                    [ "object" Aeson..=
                        Aeson.object
                            [ "object" Aeson..= ("checkout.session" :: Text)
                            , "id" Aeson..= ("cs_missing_snapshot_mode" :: Text)
                            , "customer" Aeson..= customerId
                            , "subscription" Aeson..= subscriptionId
                            , "status" Aeson..= ("complete" :: Text)
                            ]
                    ]
            ]

checkoutSessionEventWithObjectTypes :: Text -> Text -> Text -> LByteString.ByteString
checkoutSessionEventWithObjectTypes eventObjectType snapshotObjectType eventId =
    Aeson.encode $
        Aeson.object
            [ "id" Aeson..= eventId
            , "object" Aeson..= eventObjectType
            , "created" Aeson..= testStripeEventCreatedSeconds
            , "type" Aeson..= ("checkout.session.completed" :: Text)
            , "livemode" Aeson..= False
            , "api_version" Aeson..= pinnedStripeApiVersion
            , "data" Aeson..=
                Aeson.object
                    [ "object" Aeson..=
                        Aeson.object
                            [ "object" Aeson..= snapshotObjectType
                            , "id" Aeson..= ("cs_wrong_object" :: Text)
                            , "livemode" Aeson..= False
                            , "customer" Aeson..= ("cus_wrong_object" :: Text)
                            , "subscription" Aeson..= ("sub_wrong_object" :: Text)
                            , "status" Aeson..= ("complete" :: Text)
                            ]
                    ]
            ]

checkoutSessionEventWithoutLivemode :: Text -> Text -> Text -> LByteString.ByteString
checkoutSessionEventWithoutLivemode eventId customerId subscriptionId =
    Aeson.encode $
        Aeson.object
            [ "id" Aeson..= eventId
            , "object" Aeson..= ("event" :: Text)
            , "created" Aeson..= testStripeEventCreatedSeconds
            , "type" Aeson..= ("checkout.session.completed" :: Text)
            , "api_version" Aeson..= pinnedStripeApiVersion
            , "data" Aeson..=
                Aeson.object
                    [ "object" Aeson..=
                        Aeson.object
                            [ "object" Aeson..= ("checkout.session" :: Text)
                            , "id" Aeson..= ("cs_missing_mode_123" :: Text)
                            , "livemode" Aeson..= False
                            , "customer" Aeson..= customerId
                            , "subscription" Aeson..= subscriptionId
                            , "status" Aeson..= ("complete" :: Text)
                            ]
                    ]
            ]

invoicePaymentFailedEvent :: Text -> Text -> Text -> LByteString.ByteString
invoicePaymentFailedEvent = invoicePaymentFailedEventAt testStripeEventCreatedSeconds

invoicePaymentFailedEventAt :: Integer -> Text -> Text -> Text -> LByteString.ByteString
invoicePaymentFailedEventAt eventCreatedAt =
    invoicePaymentFailedEventForPeriodAt eventCreatedAt 1760000000 1762592000

invoicePaymentFailedEventForPeriodAt :: Integer -> Integer -> Integer -> Text -> Text -> Text -> LByteString.ByteString
invoicePaymentFailedEventForPeriodAt eventCreatedAt periodStart periodEnd eventId customerId subscriptionId =
    Aeson.encode $
        Aeson.object
            [ "id" Aeson..= eventId
            , "object" Aeson..= ("event" :: Text)
            , "created" Aeson..= eventCreatedAt
            , "type" Aeson..= ("invoice.payment_failed" :: Text)
            , "livemode" Aeson..= False
            , "api_version" Aeson..= pinnedStripeApiVersion
            , "data" Aeson..=
                Aeson.object
                    [ "object" Aeson..=
                        Aeson.object
                            [ "object" Aeson..= ("invoice" :: Text)
                            , "id" Aeson..= ("in_failed_123" :: Text)
                            , "livemode" Aeson..= False
                            , "customer" Aeson..= customerId
                            , "subscription" Aeson..= subscriptionId
                            , "period_start" Aeson..= periodStart
                            , "period_end" Aeson..= periodEnd
                            ]
                    ]
            ]

unknownEvent :: Text -> Venue -> LByteString.ByteString
unknownEvent eventId venue =
    Aeson.encode $
        Aeson.object
            [ "id" Aeson..= eventId
            , "object" Aeson..= ("event" :: Text)
            , "created" Aeson..= testStripeEventCreatedSeconds
            , "type" Aeson..= ("customer.created" :: Text)
            , "livemode" Aeson..= False
            , "api_version" Aeson..= pinnedStripeApiVersion
            , "data" Aeson..=
                Aeson.object
                    [ "object" Aeson..=
                        Aeson.object
                            [ "object" Aeson..= ("customer" :: Text)
                            , "id" Aeson..= ("cus_ignored_123" :: Text)
                            , "livemode" Aeson..= False
                            , "metadata" Aeson..= Aeson.object ["venue_id" Aeson..= inputValue venue.id]
                            ]
                    ]
            ]

testStripeEventCreatedSeconds :: Integer
testStripeEventCreatedSeconds = 1784678460

testStripeConfig :: StripeConfig
testStripeConfig =
    StripeConfig
        { secretKey = "sk_test_redacted"
        , webhookSecret = "whsec_test"
        , priceLookupKey = Just defaultPriceLookupKey
        , priceId = Nothing
        , appBaseUrl = "http://localhost"
        , stripeMode = StripeTestMode
        , stripeDeploymentControls =
            StripeDeploymentControls
                { stripeBillingEnabled = True
                , stripeCheckoutEnabled = True
                , stripeOwnerNavigationVisible = False
                }
        }

runWebhookInThread :: (?modelContext :: ModelContext) => LByteString.ByteString -> MVar (Either SomeException (Either Text BillingWebhookResult)) -> IO ()
runWebhookInThread eventBody result = do
    _ <- forkIO (try (handleStripeWebhookPayload StripeTestMode eventBody) >>= putMVar result)
    pure ()

isSuccessfulWebhookDelivery :: Either SomeException (Either Text BillingWebhookResult) -> Bool
isSuccessfulWebhookDelivery = \case
    Right (Right _) -> True
    _               -> False

isProcessed :: BillingWebhookResult -> Bool
isProcessed (BillingWebhookProcessed _) = True
isProcessed _                           = False

isDuplicate :: BillingWebhookResult -> Bool
isDuplicate (BillingWebhookDuplicate _) = True
isDuplicate _                           = False

isIgnored :: BillingWebhookResult -> Bool
isIgnored (BillingWebhookIgnored _) = True
isIgnored _                         = False

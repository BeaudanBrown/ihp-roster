module Test.BillingReconciliationSpec where

import Application.Async.Queue (EnqueueAppJobResult (EnqueuedAppJob),
                                appJobMaxAttempts)
import Application.Async.Registry (dispatchAppJob)
import Application.Billing.Reconciliation
import Application.Billing.Stripe
import Application.EmailDelivery (emailDeliveryJobKind)
import Application.Helper.FrontendContract.Surface.Billing.Resource (billingResource)
import Application.Helper.LiveUpdate.DurableCodec (DurableResource (..),
                                                   decodeDurableResource)
import Config (config)
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (withFrameworkConfig)
import IHP.Job.Types (JobStatus (JobStatusRunning, JobStatusSucceeded))
import Test.Hspec
import Test.Support

import IHP.Test.Mocking

billingNotificationJobKind :: Text
billingNotificationJobKind = emailDeliveryJobKind

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Billing reconciliation" do
        it "repairs a known completed Checkout from current Stripe state without changing venue writability" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Reconciliation Venue"
                owner <- createUserRecord "billing-reconciliation-owner@example.com" "staff" True
                now <- getCurrentTime
                _ <-
                    newRecord @VenueBillingControl
                        |> set #venueId (unpackId venue.id)
                        |> set #manualReadOnly True
                        |> set #manualReadOnlyReason (Just "Founder hold")
                        |> set #setByUserId (Just (unpackId owner.id))
                        |> set #setAt (Just now)
                        |> createRecord
                attempt <-
                    newRecord @BillingCheckoutAttempt
                        |> set #venueId (unpackId venue.id)
                        |> set #initiatedByUserId (unpackId owner.id)
                        |> set #livemode False
                        |> set #stripeCustomerId "cus_reconcile_123"
                        |> set #stripePriceId "price_stale_123"
                        |> set #stripeCheckoutSessionId (Just "cs_reconcile_123")
                        |> set #status "open"
                        |> createRecord

                result <- reconcileKnownCheckoutAttempt (reconciliationStripeClient venue) testStripeConfig attempt

                subscription <- case result of
                    Right (BillingSubscriptionReconciled reconciledSubscription) -> pure reconciledSubscription
                    other -> expectationFailure (cs ("expected reconciled Subscription, got " <> tshow other)) >> fail "unreachable"
                subscription.stripeSubscriptionId `shouldBe` "sub_reconcile_123"
                subscription.stripePriceId `shouldBe` "price_current_123"
                subscription.status `shouldBe` "active"
                subscription.cancelAtPeriodEnd `shouldBe` True
                subscription.currentPeriodStart `shouldSatisfy` isJust
                subscription.currentPeriodEnd `shouldSatisfy` isJust
                subscription.lastAppliedStripeEventCreatedAt `shouldSatisfy` isJust
                subscription.lastAppliedStripeEventId `shouldSatisfy` maybe False (Text.isPrefixOf "~billing-reconciliation:")
                subscription.lastSyncedAt `shouldSatisfy` (> now)

                customer <- query @VenueBillingCustomer |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                customer.stripeCustomerId `shouldBe` "cus_reconcile_123"
                customer.livemode `shouldBe` False
                customer.createdByUserId `shouldBe` Nothing

                updatedAttempt <- fetch attempt.id
                updatedAttempt.status `shouldBe` "completed"
                updatedAttempt.stripeSubscriptionId `shouldBe` Just "sub_reconcile_123"
                updatedAttempt.completedAt `shouldSatisfy` isJust
                updatedAttempt.errorCode `shouldBe` Nothing
                updatedAttempt.errorSummary `shouldBe` Nothing

                control <- query @VenueBillingControl |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                control.manualReadOnly `shouldBe` True
                control.manualReadOnlyReason `shouldBe` Just "Founder hold"

        it "refreshes a known stale Subscription and repairs its Customer association" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Subscription Reconciliation Venue"
                now <- getCurrentTime
                subscription <-
                    newRecord @VenueSubscription
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeSubscriptionId "sub_reconcile_123"
                        |> set #stripePriceId "price_stale_123"
                        |> set #livemode False
                        |> set #status "past_due"
                        |> set #cancelAtPeriodEnd False
                        |> set #lastSyncedAt (addUTCTime (-3600) now)
                        |> createRecord

                result <- reconcileKnownSubscription (reconciliationStripeClient venue) testStripeConfig subscription

                reconciled <- case result of
                    Right (BillingSubscriptionReconciled currentSubscription) -> pure currentSubscription
                    other -> expectationFailure (cs ("expected reconciled Subscription, got " <> tshow other)) >> fail "unreachable"
                reconciled.id `shouldBe` subscription.id
                reconciled.stripePriceId `shouldBe` "price_current_123"
                reconciled.status `shouldBe` "active"
                reconciled.cancelAtPeriodEnd `shouldBe` True
                reconciled.currentPeriodStart `shouldSatisfy` isJust
                reconciled.currentPeriodEnd `shouldSatisfy` isJust
                reconciled.lastAppliedStripeEventCreatedAt `shouldSatisfy` isJust
                reconciled.lastAppliedStripeEventId `shouldSatisfy` maybe False (Text.isPrefixOf "~billing-reconciliation:")
                reconciled.lastSyncedAt `shouldSatisfy` (> now)

                customer <- query @VenueBillingCustomer |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                customer.stripeCustomerId `shouldBe` "cus_reconcile_123"
                customer.createdByUserId `shouldBe` Nothing

        it "rejects mismatched provider venue metadata without mutating local state" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Metadata Venue"
                otherVenue <- createVenueWithConfig "Billing Other Metadata Venue"
                subscription <-
                    newRecord @VenueSubscription
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeSubscriptionId "sub_reconcile_123"
                        |> set #stripePriceId "price_stale_123"
                        |> set #livemode False
                        |> set #status "past_due"
                        |> set #cancelAtPeriodEnd False
                        |> createRecord

                result <- reconcileKnownSubscription (reconciliationStripeClient otherVenue) testStripeConfig subscription

                result `shouldBe` Left BillingReconciliationFailure
                    { reconciliationFailureCode = "subscription_metadata_mismatch"
                    , reconciliationFailureSummary = "The Stripe Subscription venue metadata does not match this venue."
                    }
                unchanged <- fetch subscription.id
                unchanged.status `shouldBe` "past_due"
                unchanged.stripePriceId `shouldBe` "price_stale_123"
                query @VenueBillingCustomer |> fetchCount `shouldReturn` 0

        it "does not overwrite a Subscription whose provider event cursor advanced after target selection" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Reconciliation Ordering Venue"
                selectedSubscription <-
                    newRecord @VenueSubscription
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeSubscriptionId "sub_reconcile_123"
                        |> set #stripePriceId "price_stale_123"
                        |> set #livemode False
                        |> set #status "past_due"
                        |> set #cancelAtPeriodEnd False
                        |> createRecord
                advancedAt <- getCurrentTime
                _ <-
                    selectedSubscription
                        |> set #status "unpaid"
                        |> set #lastAppliedStripeEventCreatedAt (Just advancedAt)
                        |> set #lastAppliedStripeEventId (Just "evt_advanced_after_selection")
                        |> updateRecord

                result <- reconcileKnownSubscription (reconciliationStripeClient venue) testStripeConfig selectedSubscription

                result `shouldBe` Left BillingReconciliationFailure
                    { reconciliationFailureCode = "local_subscription_advanced"
                    , reconciliationFailureSummary = "The local Subscription advanced while reconciliation was reading Stripe."
                    }
                unchanged <- fetch selectedSubscription.id
                unchanged.status `shouldBe` "unpaid"
                unchanged.lastAppliedStripeEventId `shouldBe` Just "evt_advanced_after_selection"
                query @VenueBillingCustomer |> fetchCount `shouldReturn` 0

        it "does not overwrite a selected Subscription whose cursor is later than the observation barrier" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Reconciliation Selected Ordering Venue"
                now <- getCurrentTime
                selectedSubscription <-
                    newRecord @VenueSubscription
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeSubscriptionId "sub_reconcile_123"
                        |> set #stripePriceId "price_webhook_current_123"
                        |> set #livemode False
                        |> set #status "unpaid"
                        |> set #cancelAtPeriodEnd False
                        |> set #lastAppliedStripeEventCreatedAt (Just (addUTCTime 60 now))
                        |> set #lastAppliedStripeEventId (Just "evt_later_than_observation")
                        |> createRecord

                result <- reconcileKnownSubscription (reconciliationStripeClient venue) testStripeConfig selectedSubscription

                result `shouldBe` Left BillingReconciliationFailure
                    { reconciliationFailureCode = "local_subscription_advanced"
                    , reconciliationFailureSummary = "The local Subscription is newer than the reconciliation observation boundary."
                    }
                unchanged <- fetch selectedSubscription.id
                unchanged.status `shouldBe` "unpaid"
                unchanged.stripePriceId `shouldBe` "price_webhook_current_123"
                unchanged.lastAppliedStripeEventId `shouldBe` Just "evt_later_than_observation"
                query @VenueBillingCustomer |> fetchCount `shouldReturn` 0

        it "queues one deduplicated reconciliation job for each known non-terminal Subscription" $ withContext do
            withCleanDb do
                forM_ ["incomplete", "trialing", "active", "past_due", "unpaid", "paused", "canceled", "incomplete_expired"] \status -> do
                    venue <- createVenueWithConfig ("Billing Sweep " <> status)
                    _ <-
                        newRecord @VenueSubscription
                            |> set #venueId (unpackId venue.id)
                            |> set #stripeSubscriptionId ("sub_sweep_" <> status)
                            |> set #stripePriceId "price_current_123"
                            |> set #livemode False
                            |> set #status status
                            |> set #cancelAtPeriodEnd False
                            |> createRecord
                    pure ()

                firstSummary <- enqueueBillingReconciliationSweep
                secondSummary <- enqueueBillingReconciliationSweep

                firstSummary.eligibleSubscriptionCount `shouldBe` 6
                firstSummary.enqueuedJobCount `shouldBe` 6
                firstSummary.existingJobCount `shouldBe` 0
                secondSummary.eligibleSubscriptionCount `shouldBe` 6
                secondSummary.enqueuedJobCount `shouldBe` 0
                secondSummary.existingJobCount `shouldBe` 6
                jobs <- query @AppJob |> filterWhere (#jobKind, billingReconciliationJobKind) |> fetch
                length jobs `shouldBe` 6
                map (.relatedTable) jobs `shouldSatisfy` all (== Just "venue_subscriptions")
                map (.venueId) jobs `shouldSatisfy` all isJust

        it "dispatches queued reconciliation through the shared worker behavior" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Reconciliation Worker Venue"
                subscription <-
                    newRecord @VenueSubscription
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeSubscriptionId "sub_reconcile_123"
                        |> set #stripePriceId "price_stale_123"
                        |> set #livemode False
                        |> set #status "past_due"
                        |> set #cancelAtPeriodEnd False
                        |> createRecord
                EnqueuedAppJob appJob <- enqueueBillingSubscriptionReconciliation Nothing subscription

                withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest (reconciliationStripeClient venue) do
                        withFrameworkConfig config \frameworkConfig -> do
                            let ?context = frameworkConfig
                            dispatchAppJob appJob

                completedJob <- fetch appJob.id
                completedJob.status `shouldBe` JobStatusSucceeded
                cs (Aeson.encode completedJob.result) `shouldSatisfy` Text.isInfixOf "subscription_reconciled"
                updatedSubscription <- fetch subscription.id
                updatedSubscription.status `shouldBe` "active"
                updatedSubscription.stripePriceId `shouldBe` "price_current_123"
                [durableEvent] <- query @LiveInvalidationEvent |> filterWhere (#source, "billing.reconciliation.complete" :: Text) |> fetch
                [durableEventResource] <- query @LiveInvalidationEventResource |> filterWhere (#eventId, unpackId durableEvent.id) |> fetch
                decoded <- either (\failure -> expectationFailure (cs failure) >> error "unreachable") pure (decodeDurableResource durableEventResource.resourceKey durableEventResource.resourcePayload)
                decoded.durableResourceValue `shouldBe` billingResource (unpackId venue.id)

        it "sanitizes provider failures and notifies support only on the final retry" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Reconciliation Failure Venue"
                _ <- createUserRecordWithPlatformRole "billing-reconciliation-failure-support@example.com" "staff" (Just SuperAdmin) True
                subscription <-
                    newRecord @VenueSubscription
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeSubscriptionId "sub_reconcile_123"
                        |> set #stripePriceId "price_stale_123"
                        |> set #livemode False
                        |> set #status "past_due"
                        |> set #cancelAtPeriodEnd False
                        |> createRecord
                EnqueuedAppJob queuedJob <- enqueueBillingSubscriptionReconciliation Nothing subscription
                finalAttempt <-
                    queuedJob
                        |> set #status JobStatusRunning
                        |> set #attemptsCount appJobMaxAttempts
                        |> updateRecord
                let unsafeProviderFailureClient =
                        (reconciliationStripeClient venue)
                            { retrieveSubscription = \_ _ ->
                                pure (Left (StripeHttpError "sk_live_secret pm_secret card 4111111111111111 billing@example.test"))
                            }

                dispatchResult <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest unsafeProviderFailureClient do
                        withFrameworkConfig config \frameworkConfig -> do
                            let ?context = frameworkConfig
                            Exception.try (dispatchAppJob finalAttempt) :: IO (Either Exception.SomeException ())

                case dispatchResult of
                    Left err -> do
                        let message = cs (Exception.displayException err) :: Text
                        message `shouldSatisfy` Text.isInfixOf "subscription_retrieve_failed"
                        message `shouldNotSatisfy` Text.isInfixOf "sk_live_secret"
                        message `shouldNotSatisfy` Text.isInfixOf "4111111111111111"
                        message `shouldNotSatisfy` Text.isInfixOf "billing@example.test"
                    Right () -> expectationFailure "expected provider retrieval failure"
                [notificationJob] <- query @AppJob |> filterWhere (#jobKind, billingNotificationJobKind) |> fetch
                cs (Aeson.encode notificationJob.payload) `shouldNotContain` "sk_live_secret"
                cs (Aeson.encode notificationJob.payload) `shouldNotContain` "4111111111111111"

testStripeConfig :: StripeConfig
testStripeConfig =
    StripeConfig
        { secretKey = "sk_test_redacted"
        , webhookSecret = "whsec_test_redacted"
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

reconciliationStripeClient :: Venue -> StripeClient
reconciliationStripeClient venue =
    failingStripeClient
        { retrieveCheckoutSession = \_ sessionId customerId ->
            pure $ Right StripeCheckoutSession
                { stripeCheckoutSessionId = sessionId
                , stripeCheckoutSessionUrl = Nothing
                , stripeCheckoutCustomerId = Just customerId
                , stripeCheckoutSubscriptionId = Just "sub_reconcile_123"
                , stripeCheckoutClientReferenceId = Just reconciliationVenueId
                , stripeCheckoutVenueId = Just reconciliationVenueId
                , stripeCheckoutLivemode = False
                , stripeCheckoutMode = "subscription"
                , stripeCheckoutStatus = "complete"
                , stripeCheckoutExpiresAt = 2000000000
                }
        , retrieveSubscription = \_ subscriptionId ->
            pure $ Right StripeSubscription
                { stripeSubscriptionId = subscriptionId
                , stripeSubscriptionCustomerId = "cus_reconcile_123"
                , stripeSubscriptionVenueId = Just reconciliationVenueId
                , stripeSubscriptionLivemode = False
                , stripeSubscriptionStatus = "active"
                , stripeSubscriptionPriceId = "price_current_123"
                , stripeSubscriptionPriceLivemode = False
                , stripeSubscriptionCurrentPeriodStart = 1784678400
                , stripeSubscriptionCurrentPeriodEnd = 1787356800
                , stripeSubscriptionCancelAtPeriodEnd = True
                }
        }
  where
    reconciliationVenueId = inputValue venue.id

failingStripeClient :: StripeClient
failingStripeClient =
    StripeClient
        { listPrices = \_ -> pure (Left (StripeHttpError "unexpected listPrices"))
        , retrievePrice = \_ _ -> pure (Left (StripeHttpError "unexpected retrievePrice"))
        , createCustomer = \_ _ _ _ -> pure (Left (StripeHttpError "unexpected createCustomer"))
        , createCheckoutSession = \_ _ _ _ _ _ _ -> pure (Left (StripeHttpError "unexpected createCheckoutSession"))
        , retrieveCheckoutSession = \_ _ _ -> pure (Left (StripeHttpError "unexpected retrieveCheckoutSession"))
        , createPortalSession = \_ _ _ _ _ -> pure (Left (StripeHttpError "unexpected createPortalSession"))
        , retrieveSubscription = \_ _ -> pure (Left (StripeHttpError "unexpected retrieveSubscription"))
        }

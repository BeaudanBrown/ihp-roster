module Test.Controller.BillingSpec where

import Application.Billing.Checkout
import Application.Billing.Reconciliation (billingReconciliationJobKind,
                                           performBillingReconciliationJob)
import Application.Billing.Stripe
import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import Application.Job.App ()
import Config
import qualified Control.Concurrent as Concurrent
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LByteString
import qualified Data.IORef as IORef
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (FrameworkConfig, option, withFrameworkConfig)
import IHP.Job.Queue.Result (jobDidFail)
import IHP.Job.Types (JobStatus (JobStatusFailed))
import qualified IHP.Log as Log
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import qualified Network.HTTP.Types.URI as URI
import Network.Wai (responseHeaders)
import qualified Network.Wai as Wai
import Test.Hspec
import Test.Support
import Web.Controller.Billing ()
import Web.FrontController ()
import Web.Routes
import Web.Types

withCapturedLogger :: (FrameworkConfig -> IO value) -> IO (value, Text)
withCapturedLogger action = do
    capturedRef <- IORef.newIORef []
    logger <-
        Log.newLogger
            def
                { Log.destination =
                    Log.Callback
                        (\line -> IORef.modifyIORef' capturedRef (TextEncoding.decodeUtf8 (Log.fromLogStr line) :))
                        (pure ())
                }
    result <- withFrameworkConfig (option logger >> config) action
    captured <- Text.concat . reverse <$> IORef.readIORef capturedRef
    pure (result, captured)

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "BillingController" do
        it "redirects unauthenticated users from billing" $ withContext do
            response <- callAction BillingAction
            response `responseStatusShouldBe` status302

        it "shows customer-ready billing status to owners without fresh passkey step-up" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Owner Venue"
                owner <- createUserRecord "billing-owner-page@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createTestPasskeyRecord owner "Billing owner passkey"
                _ <-
                    newRecord @BillingEvent
                        |> set #stripeEventId "evt_owner_hidden_123"
                        |> set #eventType "customer.subscription.updated"
                        |> set #livemode False
                        |> set #venueId (Just (unpackId venue.id))
                        |> set #providerObjectId (Just "sub_owner_hidden_123")
                        |> set #status "failed"
                        |> set #errorSummary (Just "internal owner-hidden diagnostic")
                        |> createRecord

                response <- withStripeConfigForTest (Right testStripeConfig) do
                    withUserAndCurrentVenue owner venue.id do
                        callAction BillingAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Billing"
                response `responseBodyShouldContain` "data-bepis-surface=\"billing\""
                response `responseBodyShouldContain` "billing-status-fragment"
                response `responseBodyShouldContain` "billing:"
                response `responseBodyShouldContain` "AUD 100/month"
                response `responseBodyShouldContain` "No subscription"
                response `responseBodyShouldContain` "Start Subscription"
                response `responseBodyShouldNotContain` "Manual Controls"
                response `responseBodyShouldNotContain` "Recent Stripe events"
                response `responseBodyShouldNotContain` "data-billing-founder-diagnostics"
                response `responseBodyShouldNotContain` "evt_owner_hidden_123"
                response `responseBodyShouldNotContain` "sub_owner_hidden_123"
                response `responseBodyShouldNotContain` "internal owner-hidden diagnostic"

        it "excludes sensitive provider data across persistence, jobs, audit summaries, owner HTML, and captured logs" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Sensitive Boundary Venue"
                owner <- createUserRecord "billing-sensitive-boundary@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createTestPasskeyRecord owner "Billing sensitive boundary passkey"
                let sensitiveValues =
                        [ "sk_live_sensitive_123"
                        , "pm_secret_sensitive_123"
                        , "4111111111111111"
                        , "payer-sensitive@example.test"
                        , "1 Sensitive Billing Street"
                        , "AU-TAX-SENSITIVE-123"
                        ]
                let rawProviderError = Text.intercalate " " sensitiveValues
                let sensitiveFailureClient =
                        checkoutStripeClient
                            { createCheckoutSession = \_ _ _ _ _ _ _ -> pure (Left (StripeHttpError rawProviderError))
                            }

                checkoutResponse <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest sensitiveFailureClient do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingCheckoutSessionAction

                checkoutResponse `responseStatusShouldBe` status302
                attempt <- query @BillingCheckoutAttempt |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                attempt.errorCode `shouldBe` Just "stripe_checkout_create_failed"
                let sanitizedSummary = fromMaybe "" attempt.errorSummary
                sanitizedSummary `shouldBe` stripeClientErrorText (StripeHttpError rawProviderError)
                jobAttempt <-
                    attempt
                        |> set #stripeCheckoutSessionId (Just "cs_sensitive_boundary")
                        |> updateRecord
                event <-
                    newRecord @BillingEvent
                        |> set #stripeEventId "evt_sensitive_boundary"
                        |> set #eventType "customer.subscription.updated"
                        |> set #livemode False
                        |> set #venueId (Just (unpackId venue.id))
                        |> set #status "failed"
                        |> set #errorSummary (Just sanitizedSummary)
                        |> createRecord
                appJob <-
                    newRecord @AppJob
                        |> set #jobKind billingReconciliationJobKind
                        |> set #venueId (Just (unpackId venue.id))
                        |> set #relatedTable (Just "billing_checkout_attempts")
                        |> set #relatedId (Just (unpackId jobAttempt.id))
                        |> set #attemptsCount 10
                        |> set #payload (Aeson.object ["target" Aeson..= ("checkout_attempt" :: Text), "localRecordId" Aeson..= inputValue jobAttempt.id, "summary" Aeson..= sanitizedSummary])
                        |> createRecord
                let jobFailureClient =
                        failingStripeClient
                            { retrieveCheckoutSession = \_ _ _ -> pure (Left (StripeHttpError rawProviderError))
                            }
                jobResult <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest jobFailureClient do
                        Exception.try (performBillingReconciliationJob appJob)
                            :: IO (Either Exception.SomeException ())
                jobException <- case jobResult of
                    Left exception -> pure exception
                    Right () -> expectationFailure "expected the raw provider failure to fail the reconciliation job" >> error "unreachable"
                let jobExceptionText = cs (Exception.displayException jobException)
                jobExceptionText `shouldSatisfy` Text.isInfixOf "checkout_session_retrieve_failed"
                forM_ sensitiveValues \sensitiveValue ->
                    jobExceptionText `shouldSatisfy` not . Text.isInfixOf sensitiveValue

                ownerResponse <- withStripeConfigForTest (Right testStripeConfig) do
                    withUserAndCurrentVenue owner venue.id do
                        callAction BillingAction
                (_, capturedLogs) <- withCapturedLogger \frameworkConfig -> do
                    let ?context = frameworkConfig
                    jobDidFail (hasqlPool ?modelContext) appJob jobException

                ownerResponse `responseStatusShouldBe` status200
                capturedLogs `shouldSatisfy` Text.isInfixOf "Failed job with exception"
                persistedJob <- fetch appJob.id
                auditEvents <- query @AuditEvent |> filterWhere (#venueId, unpackId venue.id) |> fetch
                auditEvents `shouldSatisfy` not . null
                auditEvents `shouldSatisfy` any ((== "billing_customer_created") . (.eventType))
                ownerBody <- responseBody ownerResponse
                let auditPayloads =
                        auditEvents
                            |> map (TextEncoding.decodeUtf8 . LByteString.toStrict . Aeson.encode . (.payload))
                let persistedAndRendered =
                        [ sanitizedSummary
                        , fromMaybe "" attempt.errorSummary
                        , fromMaybe "" event.errorSummary
                        , fromMaybe "" persistedJob.lastError
                        , TextEncoding.decodeUtf8 (LByteString.toStrict (Aeson.encode persistedJob.payload))
                        , TextEncoding.decodeUtf8 (LByteString.toStrict ownerBody)
                        , capturedLogs
                        ]
                            <> auditPayloads
                forM_ sensitiveValues \sensitiveValue ->
                    persistedAndRendered `shouldSatisfy` all (not . Text.isInfixOf sensitiveValue)
                ownerResponse `responseBodyShouldNotContain` "evt_sensitive_boundary"
                ownerResponse `responseBodyShouldNotContain` "cus_checkout_123"
                ownerResponse `responseBodyShouldNotContain` "stripe_checkout_create_failed"

        it "keeps the Billing status page available when Stripe configuration is unhealthy" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Unhealthy Config Venue"
                owner <- createUserRecord "billing-unhealthy-config@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"

                response <- withStripeConfigForTest (Left "Stripe configuration is unavailable") do
                    withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                        callAction BillingAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Billing"
                response `responseBodyShouldContain` "AUD 100/month"

        it "serves the billing status fragment through the typed surface rule" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Fragment Venue"
                owner <- createUserRecord "billing-fragment-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callAction ShowbillingStatusLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"billing-status-fragment\""
                response `responseBodyShouldContain` "Start Subscription"
                response `responseBodyShouldNotContain` "id=\"app\""

        it "rejects non-owner venue members" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Manager Venue"
                manager <- createUserRecord "billing-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction BillingAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"

        it "shows support-mode founders a separate diagnostic view without payer or manual controls" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Support Venue"
                superAdmin <- createUserRecordWithPlatformRole "billing-support@example.com" "staff" (Just SuperAdminRole) True
                _ <-
                    newRecord @VenueBillingCustomer
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeCustomerId "cus_support_diagnostic_123"
                        |> set #livemode False
                        |> createRecord
                subscription <- createVenueSubscriptionWithStatus venue "past_due"
                _ <-
                    subscription
                        |> set #stripeSubscriptionId "sub_support_diagnostic_123"
                        |> updateRecord
                _ <-
                    newRecord @BillingCheckoutAttempt
                        |> set #venueId (unpackId venue.id)
                        |> set #initiatedByUserId (unpackId superAdmin.id)
                        |> set #livemode False
                        |> set #stripeCustomerId "cus_support_diagnostic_123"
                        |> set #stripePriceId "price_support_diagnostic_123"
                        |> set #stripeCheckoutSessionId (Just "cs_support_diagnostic_123")
                        |> set #status "failed"
                        |> set #errorCode (Just "checkout_support_failure")
                        |> set #errorSummary (Just "bounded support checkout failure")
                        |> createRecord
                _ <-
                    newRecord @BillingEvent
                        |> set #stripeEventId "evt_support_diagnostic_123"
                        |> set #eventType "customer.subscription.updated"
                        |> set #livemode False
                        |> set #venueId (Just (unpackId venue.id))
                        |> set #providerObjectType (Just "subscription")
                        |> set #providerObjectId (Just "sub_support_diagnostic_123")
                        |> set #status "failed"
                        |> set #errorSummary (Just "bounded support event failure")
                        |> createRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    callAction BillingAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Billing diagnostics"
                response `responseBodyShouldContain` "data-billing-founder-diagnostics=\"true\""
                response `responseBodyShouldNotContain` "data-billing-owner-view"
                response `responseBodyShouldContain` "cus_support_diagnostic_123"
                response `responseBodyShouldContain` "sub_support_diagnostic_123"
                response `responseBodyShouldContain` "cs_support_diagnostic_123"
                response `responseBodyShouldContain` "bounded support checkout failure"
                response `responseBodyShouldContain` "evt_support_diagnostic_123"
                response `responseBodyShouldContain` "bounded support event failure"
                response `responseBodyShouldContain` "Last synchronized"
                response `responseBodyShouldContain` "Synchronize with Stripe"
                response `responseBodyShouldNotContain` "Start Subscription"
                response `responseBodyShouldNotContain` "Manage Billing"
                response `responseBodyShouldNotContain` "Manual Controls"
                response `responseBodyShouldNotContain` "Manual read-only"

        it "requires fresh passkey verification before founder diagnostics" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Founder Diagnostic Step-Up Venue"
                superAdmin <- createUserRecordWithPlatformRole "billing-founder-diagnostic-step-up@example.com" "staff" (Just SuperAdminRole) True
                _ <- createTestPasskeyRecord superAdmin "Billing founder diagnostic passkey"

                response <- withUserAndCurrentVenue superAdmin venue.id do
                    callAction BillingAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/PasskeyStepUp"

        it "exposes sanitized terminal reconciliation diagnostics to founders only" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Reconciliation Diagnostics Venue"
                superAdmin <- createUserRecordWithPlatformRole "billing-reconciliation-diagnostics@example.com" "staff" (Just SuperAdminRole) True
                owner <- createUserRecord "billing-reconciliation-diagnostics-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                failedJob <-
                    newRecord @AppJob
                        |> set #jobKind billingReconciliationJobKind
                        |> set #venueId (Just (unpackId venue.id))
                        |> set #relatedTable (Just "venue_subscriptions")
                        |> set #status JobStatusFailed
                        |> set #attemptsCount 10
                        |> set #lastError (Just "subscription_metadata_mismatch: Stripe Subscription venue metadata does not match this venue.")
                        |> createRecord

                founderResponse <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    callAction BillingAction
                ownerResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callAction BillingAction

                founderResponse `responseStatusShouldBe` status200
                founderResponse `responseBodyShouldContain` "Synchronize with Stripe"
                founderResponse `responseBodyShouldContain` "subscription_metadata_mismatch"
                founderResponse `responseBodyShouldContain` (inputValue failedJob.id)
                founderResponse `responseBodyShouldNotContain` "Manual Controls"
                ownerResponse `responseStatusShouldBe` status200
                ownerResponse `responseBodyShouldNotContain` "Synchronize with Stripe"
                ownerResponse `responseBodyShouldNotContain` "subscription_metadata_mismatch"

        it "renders state-specific owner guidance and actions" $ withContext do
            forM_
                [ (Nothing, False, "No subscription", "Start Subscription", "Start a subscription for this venue")
                , (Just "active", False, "Active", "Manage Billing", "renews automatically")
                , (Just "active", True, "Cancellation scheduled", "Manage Cancellation", "will not renew")
                , (Just "past_due", False, "Payment needs attention", "Resolve Payment", "update your payment method")
                , (Just "canceled", False, "Canceled", "Restart Subscription", "subscription has ended")
                , (Just "incomplete_expired", False, "Setup expired", "Restart Subscription", "payment setup expired")
                ]
                \(maybeStatus, cancelAtPeriodEnd, stateLabel, actionLabel, guidance) -> withCleanDb do
                    venue <- createVenueWithConfig ("Billing State " <> stateLabel <> " Venue")
                    owner <- createUserRecord ("billing-state-" <> Text.replace " " "-" (Text.toLower stateLabel) <> "@example.com") "staff" True
                    _ <- createVenueMembershipRecord venue owner "venue_owner"
                    _ <- createTestPasskeyRecord owner "Billing state owner passkey"
                    now <- getCurrentTime
                    forM_ maybeStatus \status -> do
                        _ <-
                            newRecord @VenueBillingCustomer
                                |> set #venueId (unpackId venue.id)
                                |> set #stripeCustomerId ("cus_owner_hidden_" <> status)
                                |> set #livemode False
                                |> createRecord
                        subscription <- createVenueSubscriptionWithStatus venue status
                        _ <-
                            subscription
                                |> set #currentPeriodStart (Just now)
                                |> set #currentPeriodEnd (Just (addUTCTime (30 * 86400) now))
                                |> set #cancelAtPeriodEnd cancelAtPeriodEnd
                                |> updateRecord
                        pure ()

                    response <- withStripeConfigForTest (Right testStripeConfig) do
                        withUserAndCurrentVenue owner venue.id do
                            callAction BillingAction

                    response `responseStatusShouldBe` status200
                    response `responseBodyShouldContain` stateLabel
                    response `responseBodyShouldContain` actionLabel
                    response `responseBodyShouldContain` guidance
                    response `responseBodyShouldContain` "Current period"
                    response `responseBodyShouldContain` "data-bepis-navigation-loading=\"true\""
                    response `responseBodyShouldContain` "data-bepis-navigation-loading-config="
                    response `responseBodyShouldContain` "Opening Stripe"
                    forM_ maybeStatus \status -> do
                        response `responseBodyShouldNotContain` ("sub_" <> status)
                        response `responseBodyShouldNotContain` ("cus_owner_hidden_" <> status)
                        when ("_" `Text.isInfixOf` status) do
                            response `responseBodyShouldNotContain` status

        it "gates owner Billing navigation without changing direct-route authorization" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Navigation Venue"
                owner <- createUserRecord "billing-navigation-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createTestPasskeyRecord owner "Billing navigation owner passkey"
                superAdmin <- createUserRecordWithPlatformRole "billing-navigation-support@example.com" "staff" (Just SuperAdminRole) True
                _ <- createVenueMembershipRecord venue superAdmin "venue_owner"
                let hiddenConfig = testStripeConfig
                let visibleConfig =
                        testStripeConfig
                            { stripeDeploymentControls =
                                testStripeConfig.stripeDeploymentControls
                                    { stripeOwnerNavigationVisible = True
                                    }
                            }

                hiddenResponse <- withStripeConfigForTest (Right hiddenConfig) do
                    withUserAndCurrentVenue owner venue.id do
                        callAction BillingAction
                visibleResponse <- withStripeConfigForTest (Right visibleConfig) do
                    withUserAndCurrentVenue owner venue.id do
                        callAction BillingAction
                supportResponse <- withStripeConfigForTest (Right visibleConfig) do
                    withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                        callAction BillingAction

                hiddenResponse `responseStatusShouldBe` status200
                hiddenResponse `responseBodyShouldNotContain` "href=\"/Billing\""
                visibleResponse `responseStatusShouldBe` status200
                visibleResponse `responseBodyShouldContain` "href=\"/Billing\""
                supportResponse `responseStatusShouldBe` status200
                supportResponse `responseBodyShouldNotContain` "href=\"/Billing\""
                visibleBody <- (cs <$> responseBody visibleResponse) :: IO Text
                let (_, afterXero) = Text.breakOn "href=\"/Xero\"" visibleBody
                let (_, afterBilling) = Text.breakOn "href=\"/Billing\"" afterXero
                afterXero `shouldSatisfy` Text.isInfixOf "href=\"/Billing\""
                afterBilling `shouldSatisfy` Text.isInfixOf "href=\"/Admin\""

        it "prevents founder support mode from starting Checkout or opening Customer Portal" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Support Payment Boundary Venue"
                superAdmin <- createUserRecordWithPlatformRole "billing-support-payment-boundary@example.com" "staff" (Just SuperAdminRole) True
                _ <-
                    newRecord @VenueBillingCustomer
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeCustomerId "cus_portal_123"
                        |> set #livemode False
                        |> createRecord

                (checkoutResponse, portalResponse) <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest checkoutAndPortalStripeClient do
                        checkoutResponse <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                            callAction CreateBillingCheckoutSessionAction
                        portalResponse <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                            callAction CreateBillingPortalSessionAction
                        pure (checkoutResponse, portalResponse)

                lookup "Location" (responseHeaders checkoutResponse) `shouldBe` Just "http://localhost/Support"
                lookup "Location" (responseHeaders portalResponse) `shouldBe` Just "http://localhost/Support"
                query @BillingCheckoutAttempt |> filterWhere (#venueId, unpackId venue.id) |> fetchCount `shouldReturn` 0

        it "requires fresh passkey verification for each owner payment action" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Payment Step-Up Venue"
                owner <- createUserRecord "billing-payment-step-up@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createTestPasskeyRecord owner "Billing owner passkey"
                _ <-
                    newRecord @VenueBillingCustomer
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeCustomerId "cus_portal_123"
                        |> set #livemode False
                        |> createRecord

                checkoutResponse <- withUserAndCurrentVenue owner venue.id do
                    callAction CreateBillingCheckoutSessionAction
                portalResponse <- withUserAndCurrentVenue owner venue.id do
                    callAction CreateBillingPortalSessionAction

                lookup "Location" (responseHeaders checkoutResponse) `shouldBe` Just "http://localhost/PasskeyStepUp"
                lookup "Location" (responseHeaders portalResponse) `shouldBe` Just "http://localhost/PasskeyStepUp"
                query @BillingCheckoutAttempt |> filterWhere (#venueId, unpackId venue.id) |> fetchCount `shouldReturn` 0

        it "lets an owner without a passkey start Checkout when privileged strong authentication is disabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Disabled Strong Auth Checkout Venue"
                owner <- createUserRecord "billing-disabled-strong-auth-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"

                response <- withPrivilegedStrongAuthentication False do
                    withStripeConfigForTest (Right testStripeConfig) do
                        withStripeClientForTest (checkoutStripeClientExpectingCustomer "Billing Disabled Strong Auth Checkout Venue" "billing-disabled-strong-auth-owner@example.com") do
                            withUserAndCurrentVenue owner venue.id do
                                callAction CreateBillingCheckoutSessionAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "https://checkout.stripe.com/c/pay/cs_test_123"
                query @BillingCheckoutAttempt |> filterWhere (#venueId, unpackId venue.id) |> fetchCount `shouldReturn` 1

        it "rejects Checkout before Stripe calls when the owner's email is unverified" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Verified Email Venue"
                owner <- createUserRecord "billing-unverified-owner@example.com" "staff" True
                    >>= updateRecord . set #emailVerifiedAt Nothing
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                stripeCalls <- IORef.newIORef (0 :: Int)
                let client = checkoutStripeClient
                        { listPrices = \_ -> do
                            IORef.modifyIORef' stripeCalls (+ 1)
                            pure (Right [validMonthlyPrice])
                        }

                response <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest client do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingCheckoutSessionAction

                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/Billing"
                IORef.readIORef stripeCalls `shouldReturn` 0
                query @VenueBillingCustomer |> filterWhere (#venueId, unpackId venue.id) |> fetchCount `shouldReturn` 0
                query @BillingCheckoutAttempt |> filterWhere (#venueId, unpackId venue.id) |> fetchCount `shouldReturn` 0

        it "starts hosted Checkout and stores one Stripe Customer per venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Checkout Venue"
                owner <- createUserRecord "billing-checkout-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"

                response <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest (checkoutStripeClientExpectingCustomer "Billing Checkout Venue" "billing-checkout-owner@example.com") do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingCheckoutSessionAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "https://checkout.stripe.com/c/pay/cs_test_123"
                customer <- query @VenueBillingCustomer |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                customer.stripeCustomerId `shouldBe` "cus_checkout_123"
                customer.livemode `shouldBe` False
                customer.createdByUserId `shouldBe` Just (unpackId owner.id)
                attempt <- query @BillingCheckoutAttempt |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                attempt.initiatedByUserId `shouldBe` unpackId owner.id
                attempt.livemode `shouldBe` False
                attempt.stripeCustomerId `shouldBe` "cus_checkout_123"
                attempt.stripePriceId `shouldBe` "price_monthly_123"
                attempt.stripeCheckoutSessionId `shouldBe` Just "cs_checkout_123"
                attempt.status `shouldBe` "open"
                attempt.expiresAt `shouldSatisfy` isJust

        it "uses the configured direct Price without a lookup before hosted Checkout" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Direct Price Checkout Venue"
                owner <- createUserRecord "billing-direct-price-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                lookupCalls <- IORef.newIORef (0 :: Int)
                retrievedPriceIds <- IORef.newIORef ([] :: [Text])
                let directPriceConfig =
                        testStripeConfig
                            { priceLookupKey = Nothing
                            , priceId = Just "price_monthly_123"
                            }
                let directPriceClient =
                        (checkoutStripeClientExpectingCustomer "Billing Direct Price Checkout Venue" "billing-direct-price-owner@example.com")
                            { listPrices = \_ -> do
                                IORef.modifyIORef' lookupCalls (+ 1)
                                pure (Left (StripeHttpError "direct Price configuration must not list Prices"))
                            , retrievePrice = \_ priceId -> do
                                IORef.modifyIORef' retrievedPriceIds (priceId :)
                                pure (Right validMonthlyPrice)
                            }

                response <- withStripeConfigForTest (Right directPriceConfig) do
                    withStripeClientForTest directPriceClient do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingCheckoutSessionAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "https://checkout.stripe.com/c/pay/cs_test_123"
                IORef.readIORef lookupCalls `shouldReturn` 0
                IORef.readIORef retrievedPriceIds `shouldReturn` ["price_monthly_123"]
                attempt <- query @BillingCheckoutAttempt |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                attempt.stripePriceId `shouldBe` "price_monthly_123"

        it "resumes the same open Checkout Session after a repeated request" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Resumable Checkout Venue"
                owner <- createUserRecord "billing-resumable-checkout@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                createCalls <- IORef.newIORef (0 :: Int)
                retrieveCalls <- IORef.newIORef (0 :: Int)
                let client = resumableCheckoutStripeClient createCalls retrieveCalls

                (firstResponse, secondResponse) <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest client do
                        firstResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingCheckoutSessionAction
                        secondResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingCheckoutSessionAction
                        pure (firstResponse, secondResponse)

                firstResponse `responseStatusShouldBe` status302
                secondResponse `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders firstResponse) `shouldBe` Just "https://checkout.stripe.com/c/pay/cs_test_123"
                lookup "Location" (responseHeaders secondResponse) `shouldBe` Just "https://checkout.stripe.com/c/pay/cs_test_123"
                IORef.readIORef createCalls `shouldReturn` 1
                IORef.readIORef retrieveCalls `shouldReturn` 1
                query @VenueBillingCustomer |> filterWhere (#venueId, unpackId venue.id) |> fetchCount `shouldReturn` 1
                query @BillingCheckoutAttempt |> filterWhere (#venueId, unpackId venue.id) |> fetchCount `shouldReturn` 1

        it "keeps a resumed completed Checkout Session ID out of the owner progress URL" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Completed Checkout Resume Venue"
                owner <- createUserRecord "billing-completed-checkout-resume@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                attempt <- createOpenBillingCheckoutAttempt venue owner "cs_completed_resume_123"

                response <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest completedCheckoutStripeClient do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingCheckoutSessionAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response)
                    `shouldBe` Just (cs ("http://localhost/Billing?checkout=success&attempt_id=" <> inputValue attempt.id))
                lookup "Location" (responseHeaders response)
                    `shouldSatisfy` maybe False (not . ByteString.isInfixOf "cs_completed_resume_123")

        it "retries an interrupted Checkout create with the same durable attempt key" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Retried Checkout Venue"
                owner <- createUserRecord "billing-retried-checkout@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                createAttempts <- IORef.newIORef ([] :: [Text])
                let client = retryingCheckoutStripeClient createAttempts

                (interruptedResponse, retriedResponse) <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest client do
                        interruptedResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingCheckoutSessionAction
                        retriedResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingCheckoutSessionAction
                        pure (interruptedResponse, retriedResponse)

                lookup "Location" (responseHeaders interruptedResponse) `shouldBe` Just "http://localhost/Billing"
                lookup "Location" (responseHeaders retriedResponse) `shouldBe` Just "https://checkout.stripe.com/c/pay/cs_test_123"
                IORef.readIORef createAttempts >>= \case
                    [retriedAttemptId, interruptedAttemptId] -> retriedAttemptId `shouldBe` interruptedAttemptId
                    attemptIds -> expectationFailure (cs ("expected two Checkout create calls, got " <> tshow attemptIds))
                attempt <- query @BillingCheckoutAttempt |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                attempt.stripeCheckoutSessionId `shouldBe` Just "cs_checkout_123"
                attempt.errorCode `shouldBe` Nothing
                attempt.errorSummary `shouldBe` Nothing

        it "commits the attempt before an interrupted provider call" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Durable Attempt Venue"
                owner <- createUserRecord "billing-durable-attempt@example.com" "staff" True
                createAttempts <- IORef.newIORef ([] :: [Text])
                let client = crashingCheckoutStripeClient createAttempts
                let successUrlFor attemptId = "http://localhost/BillingSuccess?attempt_id=" <> inputValue attemptId <> "&session_id={CHECKOUT_SESSION_ID}"
                let cancelUrlFor attemptId = "http://localhost/BillingCancel?attempt_id=" <> inputValue attemptId

                interrupted <- Exception.try (startOrResumeCheckout client testStripeConfig venue owner successUrlFor cancelUrlFor)
                    :: IO (Either Exception.SomeException CheckoutStartResult)
                interrupted `shouldSatisfy` \case
                    Left _ -> True
                    Right _ -> False
                durableAttempt <- query @BillingCheckoutAttempt |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                durableAttempt.status `shouldBe` "open"
                durableAttempt.stripeCheckoutSessionId `shouldBe` Nothing

                retried <- startOrResumeCheckout client testStripeConfig venue owner successUrlFor cancelUrlFor
                case retried.checkoutStartOutcome of
                    CheckoutSessionReady retriedAttempt _ -> retriedAttempt.id `shouldBe` durableAttempt.id
                    outcome -> expectationFailure (cs ("expected retried Checkout Session, got " <> tshow outcome))
                IORef.readIORef createAttempts >>= \case
                    [retriedAttemptId, interruptedAttemptId] -> retriedAttemptId `shouldBe` interruptedAttemptId
                    ids -> expectationFailure (cs ("expected two provider calls for one attempt, got " <> tshow ids))

        it "expires an unusable Checkout Session before creating a fresh attempt" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Expired Checkout Venue"
                owner <- createUserRecord "billing-expired-checkout@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                createAttemptIds <- IORef.newIORef ([] :: [Text])
                let client = expiringCheckoutStripeClient createAttemptIds

                (firstResponse, restartedResponse) <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest client do
                        firstResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingCheckoutSessionAction
                        restartedResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingCheckoutSessionAction
                        pure (firstResponse, restartedResponse)

                lookup "Location" (responseHeaders firstResponse) `shouldBe` Just "https://checkout.stripe.com/c/pay/cs_expiring_1"
                lookup "Location" (responseHeaders restartedResponse) `shouldBe` Just "https://checkout.stripe.com/c/pay/cs_expiring_2"
                IORef.readIORef createAttemptIds >>= \case
                    [secondAttemptId, firstAttemptId] -> secondAttemptId `shouldNotBe` firstAttemptId
                    ids -> expectationFailure (cs ("expected two Checkout attempt ids, got " <> tshow ids))
                attempts <- query @BillingCheckoutAttempt |> filterWhere (#venueId, unpackId venue.id) |> orderByAsc #createdAt |> fetch
                map (.status) attempts `shouldBe` ["expired", "open"]
                map (.stripeCheckoutSessionId) attempts `shouldBe` [Just "cs_expiring_1", Just "cs_expiring_2"]

        it "serializes concurrent Checkout creation into one logical open operation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Concurrent Checkout Venue"
                owner <- createUserRecord "billing-concurrent-checkout@example.com" "staff" True
                createEntered <- Concurrent.newEmptyMVar
                releaseCreate <- Concurrent.newEmptyMVar
                firstResultVar <- Concurrent.newEmptyMVar
                secondResultVar <- Concurrent.newEmptyMVar
                createCalls <- IORef.newIORef (0 :: Int)
                customerCalls <- IORef.newIORef (0 :: Int)
                let client = concurrentCheckoutStripeClient createEntered releaseCreate createCalls customerCalls
                let successUrlFor attemptId = "http://localhost/BillingSuccess?attempt_id=" <> inputValue attemptId <> "&session_id={CHECKOUT_SESSION_ID}"
                let cancelUrlFor attemptId = "http://localhost/BillingCancel?attempt_id=" <> inputValue attemptId
                let runCheckout resultVar = do
                        result <- Exception.try (startOrResumeCheckout client testStripeConfig venue owner successUrlFor cancelUrlFor)
                        Concurrent.putMVar resultVar (result :: Either Exception.SomeException CheckoutStartResult)

                _ <- Concurrent.forkIO (runCheckout firstResultVar)
                Concurrent.takeMVar createEntered
                secondStarted <- Concurrent.newEmptyMVar
                _ <- Concurrent.forkIO do
                    Concurrent.putMVar secondStarted ()
                    runCheckout secondResultVar
                Concurrent.takeMVar secondStarted
                Concurrent.putMVar releaseCreate ()
                firstResult <- Concurrent.takeMVar firstResultVar
                secondResult <- Concurrent.takeMVar secondResultVar

                forM_ [firstResult, secondResult] \case
                    Left err -> expectationFailure ("concurrent Checkout failed: " <> Exception.displayException err)
                    Right result -> case result.checkoutStartOutcome of
                        CheckoutSessionReady _ _ -> pure ()
                        outcome -> expectationFailure (cs ("expected resumable Checkout Session, got " <> tshow outcome))
                IORef.readIORef createCalls `shouldReturn` 1
                IORef.readIORef customerCalls `shouldReturn` 1
                query @VenueBillingCustomer |> filterWhere (#venueId, unpackId venue.id) |> fetchCount `shouldReturn` 1
                query @BillingCheckoutAttempt |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#status, "open") |> fetchCount `shouldReturn` 1

        it "refuses Checkout redirects outside Stripe's hosted domain" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Unsafe Checkout Redirect Venue"
                owner <- createUserRecord "billing-unsafe-checkout-redirect@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"

                response <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest unsafeCheckoutRedirectClient do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingCheckoutSessionAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/Billing"

        it "blocks crafted Checkout requests when new Checkout is disabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Checkout Disabled Venue"
                owner <- createUserRecord "billing-checkout-disabled@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                let disabledConfig =
                        testStripeConfig
                            { stripeDeploymentControls =
                                testStripeConfig.stripeDeploymentControls
                                    { stripeCheckoutEnabled = False
                                    }
                            }

                pageResponse <- withStripeConfigForTest (Right disabledConfig) do
                    withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                        callAction BillingAction
                pageResponse `responseStatusShouldBe` status200
                pageResponse `responseBodyShouldContain` "New subscriptions are temporarily unavailable"

                response <- withStripeConfigForTest (Right disabledConfig) do
                    withStripeClientForTest checkoutStripeClient do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingCheckoutSessionAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/Billing"
                customerCount <- query @VenueBillingCustomer |> filterWhere (#venueId, unpackId venue.id) |> fetchCount
                customerCount `shouldBe` 0

        it "wires active-subscription Checkout rejection before Stripe calls" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Active Subscription Venue"
                owner <- createUserRecord "billing-active-subscription@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createVenueSubscriptionWithStatus venue "active"
                stripeCalls <- IORef.newIORef (0 :: Int)
                let client = checkoutStripeClient
                        { listPrices = \_ -> do
                            IORef.modifyIORef' stripeCalls (+ 1)
                            pure (Right [validMonthlyPrice])
                        }

                response <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest client do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingCheckoutSessionAction

                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/Billing"
                IORef.readIORef stripeCalls `shouldReturn` 0
                query @VenueBillingCustomer |> filterWhere (#venueId, unpackId venue.id) |> fetchCount `shouldReturn` 0
                query @BillingCheckoutAttempt |> filterWhere (#venueId, unpackId venue.id) |> fetchCount `shouldReturn` 0

        it "wires canceled-subscription restart to hosted Checkout" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Canceled Subscription Venue"
                owner <- createUserRecord "billing-canceled-subscription@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createVenueSubscriptionWithStatus venue "canceled"

                response <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest checkoutStripeClient do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingCheckoutSessionAction

                lookup "Location" (responseHeaders response) `shouldBe` Just "https://checkout.stripe.com/c/pay/cs_test_123"
                query @BillingCheckoutAttempt |> filterWhere (#venueId, unpackId venue.id) |> fetchCount `shouldReturn` 1

        it "keeps existing-customer Portal access when new Checkout is disabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Portal Venue"
                owner <- createUserRecord "billing-portal-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <-
                    newRecord @VenueBillingCustomer
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeCustomerId "cus_portal_123"
                        |> set #livemode False
                        |> createRecord

                let checkoutDisabledConfig =
                        testStripeConfig
                            { stripeDeploymentControls =
                                testStripeConfig.stripeDeploymentControls
                                    { stripeCheckoutEnabled = False
                                    }
                            }
                response <- withStripeConfigForTest (Right checkoutDisabledConfig) do
                    withStripeClientForTest portalStripeClient do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingPortalSessionAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "https://billing.stripe.com/p/session/bps_test_123"

        it "uses a fresh idempotency request identifier for every Portal action" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Fresh Portal Venue"
                owner <- createUserRecord "billing-fresh-portal-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <-
                    newRecord @VenueBillingCustomer
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeCustomerId "cus_portal_123"
                        |> set #livemode False
                        |> createRecord
                requestIds <- IORef.newIORef ([] :: [Text])
                let client = recordingPortalStripeClient requestIds

                (firstResponse, secondResponse) <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest client do
                        firstResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingPortalSessionAction
                        secondResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingPortalSessionAction
                        pure (firstResponse, secondResponse)

                lookup "Location" (responseHeaders firstResponse) `shouldBe` Just "https://billing.stripe.com/p/session/bps_test_123"
                lookup "Location" (responseHeaders secondResponse) `shouldBe` Just "https://billing.stripe.com/p/session/bps_test_123"
                IORef.readIORef requestIds >>= \case
                    [secondRequestId, firstRequestId] -> secondRequestId `shouldNotBe` firstRequestId
                    ids -> expectationFailure (cs ("expected two Portal request ids, got " <> tshow ids))

        it "refuses Customer Portal redirects outside Stripe's hosted domain" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Unsafe Portal Redirect Venue"
                owner <- createUserRecord "billing-unsafe-portal-redirect@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <-
                    newRecord @VenueBillingCustomer
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeCustomerId "cus_unsafe_portal_123"
                        |> set #livemode False
                        |> createRecord

                response <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest unsafePortalRedirectClient do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingPortalSessionAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/Billing"

        it "lets a passkey-verified founder queue per-venue reconciliation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Manual Reconciliation Venue"
                superAdmin <- createUserRecordWithPlatformRole "billing-manual-reconciliation@example.com" "staff" (Just SuperAdminRole) True
                subscription <- createVenueSubscriptionWithStatus venue "past_due"

                response <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    callAction ReconcileVenueBillingAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/Billing"
                [appJob] <- query @AppJob |> filterWhere (#jobKind, billingReconciliationJobKind) |> fetch
                appJob.venueId `shouldBe` Just (unpackId venue.id)
                appJob.relatedTable `shouldBe` Just "venue_subscriptions"
                appJob.relatedId `shouldBe` Just (unpackId subscription.id)
                appJob.requestedByUserId `shouldBe` Just (unpackId superAdmin.id)
                auditEvent <- query @AuditEvent |> filterWhere (#eventType, "billing_reconciliation_requested") |> fetchOne
                auditEvent.targetTable `shouldBe` "app_jobs"
                auditEvent.targetId `shouldBe` unpackId appJob.id

        it "requires fresh passkey step-up for founder reconciliation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Reconciliation Step-Up Venue"
                superAdmin <- createUserRecordWithPlatformRole "billing-reconciliation-step-up@example.com" "staff" (Just SuperAdminRole) True
                _ <- createTestPasskeyRecord superAdmin "Billing reconciliation passkey"
                _ <- createVenueSubscriptionWithStatus venue "active"

                response <- withUserAndCurrentVenue superAdmin venue.id do
                    callAction ReconcileVenueBillingAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/PasskeyStepUp"
                query @AppJob |> filterWhere (#jobKind, billingReconciliationJobKind) |> fetchCount `shouldReturn` 0

        it "lets a founder without a passkey reconcile billing when privileged strong authentication is disabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Disabled Strong Auth Reconciliation Venue"
                superAdmin <- createUserRecordWithPlatformRole "billing-disabled-strong-auth-founder@example.com" "staff" (Just SuperAdminRole) True
                subscription <- createVenueSubscriptionWithStatus venue "past_due"

                response <- withPrivilegedStrongAuthentication False do
                    withUserAndCurrentVenue superAdmin venue.id do
                        callAction ReconcileVenueBillingAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/Billing"
                [appJob] <- query @AppJob |> filterWhere (#jobKind, billingReconciliationJobKind) |> fetch
                appJob.relatedId `shouldBe` Just (unpackId subscription.id)

        it "denies manual reconciliation to venue owners" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Owner Reconciliation Boundary Venue"
                owner <- createUserRecord "billing-owner-reconciliation-boundary@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createVenueSubscriptionWithStatus venue "active"

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callAction ReconcileVenueBillingAction

                response `responseStatusShouldBe` status302
                query @AppJob |> filterWhere (#jobKind, billingReconciliationJobKind) |> fetchCount `shouldReturn` 0

        it "lets support-mode super admins update manual read-only state" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Toggle Venue"
                superAdmin <- createUserRecordWithPlatformRole "billing-toggle-support@example.com" "staff" (Just SuperAdminRole) True

                response <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    callActionWithParams
                        UpdateVenueBillingControlAction
                        [ ("manualReadOnly", "true")
                        , ("manualReadOnlyReason", "Payment follow-up")
                        ]

                response `responseStatusShouldBe` status302
                control <- query @VenueBillingControl |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                control.manualReadOnly `shouldBe` True
                control.manualReadOnlyReason `shouldBe` Just "Payment follow-up"
                control.setByUserId `shouldBe` Just (unpackId superAdmin.id)

        it "returns Checkout success to Billing with a webhook-pending modal" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Success Venue"
                owner <- createUserRecord "billing-success-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                attempt <- createOpenBillingCheckoutAttempt venue owner "cs_test_123"

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callActionWithParams BillingSuccessAction
                        [ ("attempt_id", cs (inputValue attempt.id))
                        , ("session_id", "cs_test_123")
                        ]

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response)
                    `shouldBe` Just (cs ("http://localhost/Billing?checkout=success&attempt_id=" <> inputValue attempt.id))
                subscriptionCount <- query @VenueSubscription |> filterWhere (#venueId, unpackId venue.id) |> fetchCount
                subscriptionCount `shouldBe` 0

        it "queues fallback reconciliation for an exact Checkout return" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Return Reconciliation Venue"
                owner <- createUserRecord "billing-return-reconciliation@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                attempt <- createOpenBillingCheckoutAttempt venue owner "cs_reconcile_return_123"

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callActionWithParams BillingSuccessAction
                        [ ("attempt_id", cs (inputValue attempt.id))
                        , ("session_id", "cs_reconcile_return_123")
                        ]

                response `responseStatusShouldBe` status302
                [appJob] <- query @AppJob |> filterWhere (#jobKind, billingReconciliationJobKind) |> fetch
                appJob.venueId `shouldBe` Just (unpackId venue.id)
                appJob.relatedTable `shouldBe` Just "billing_checkout_attempts"
                appJob.relatedId `shouldBe` Just (unpackId attempt.id)
                appJob.requestedByUserId `shouldBe` Just (unpackId owner.id)
                unchangedAttempt <- fetch attempt.id
                unchangedAttempt.status `shouldBe` "open"
                query @VenueSubscription |> filterWhere (#venueId, unpackId venue.id) |> fetchCount `shouldReturn` 0

        it "queues fallback reconciliation when Checkout completed before its Subscription mirror arrived" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Completed Return Reconciliation Venue"
                owner <- createUserRecord "billing-completed-return-reconciliation@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                now <- getCurrentTime
                attempt <-
                    createOpenBillingCheckoutAttempt venue owner "cs_completed_reconcile_return_123"
                        >>= updateRecord
                            . set #completedAt (Just now)
                            . set #stripeSubscriptionId (Just "sub_completed_reconcile_return_123")
                            . set #status "completed"

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callActionWithParams BillingSuccessAction
                        [ ("attempt_id", cs (inputValue attempt.id))
                        , ("session_id", "cs_completed_reconcile_return_123")
                        ]

                response `responseStatusShouldBe` status302
                [appJob] <- query @AppJob |> filterWhere (#jobKind, billingReconciliationJobKind) |> fetch
                appJob.relatedId `shouldBe` Just (unpackId attempt.id)
                query @VenueSubscription |> filterWhere (#venueId, unpackId venue.id) |> fetchCount `shouldReturn` 0

        it "rejects Checkout success parameters for another venue or Session" $ withContext do
            withCleanDb do
                sourceVenue <- createVenueWithConfig "Billing Return Source Venue"
                sourceOwner <- createUserRecord "billing-return-source@example.com" "staff" True
                _ <- createVenueMembershipRecord sourceVenue sourceOwner "venue_owner"
                sourceAttempt <- createOpenBillingCheckoutAttempt sourceVenue sourceOwner "cs_source_123"
                currentVenue <- createVenueWithConfig "Billing Return Current Venue"
                currentOwner <- createUserRecord "billing-return-current@example.com" "staff" True
                _ <- createVenueMembershipRecord currentVenue currentOwner "venue_owner"
                currentAttempt <- createOpenBillingCheckoutAttempt currentVenue currentOwner "cs_current_123"

                crossVenueResponse <- withPasskeyVerifiedUserAndCurrentVenue currentOwner currentVenue.id do
                    callActionWithParams BillingSuccessAction
                        [ ("attempt_id", cs (inputValue sourceAttempt.id))
                        , ("session_id", "cs_source_123")
                        ]
                wrongSessionResponse <- withPasskeyVerifiedUserAndCurrentVenue currentOwner currentVenue.id do
                    callActionWithParams BillingSuccessAction
                        [ ("attempt_id", cs (inputValue currentAttempt.id))
                        , ("session_id", "cs_forged_123")
                        ]

                lookup "Location" (responseHeaders crossVenueResponse) `shouldBe` Just "http://localhost/Billing"
                lookup "Location" (responseHeaders wrongSessionResponse) `shouldBe` Just "http://localhost/Billing"

        it "renders cancellation only for this venue's stored Checkout Session" $ withContext do
            withCleanDb do
                sourceVenue <- createVenueWithConfig "Billing Cancel Source Venue"
                sourceOwner <- createUserRecord "billing-cancel-source@example.com" "staff" True
                _ <- createVenueMembershipRecord sourceVenue sourceOwner "venue_owner"
                sourceAttempt <- createOpenBillingCheckoutAttempt sourceVenue sourceOwner "cs_cancel_source_123"
                currentVenue <- createVenueWithConfig "Billing Cancel Current Venue"
                currentOwner <- createUserRecord "billing-cancel-current@example.com" "staff" True
                _ <- createVenueMembershipRecord currentVenue currentOwner "venue_owner"
                currentAttempt <- createOpenBillingCheckoutAttempt currentVenue currentOwner "cs_cancel_current_123"

                validResponse <- withPasskeyVerifiedUserAndCurrentVenue currentOwner currentVenue.id do
                    callActionWithParams BillingCancelAction
                        [("attempt_id", cs (inputValue currentAttempt.id))]
                crossVenueResponse <- withPasskeyVerifiedUserAndCurrentVenue currentOwner currentVenue.id do
                    callActionWithParams BillingCancelAction
                        [("attempt_id", cs (inputValue sourceAttempt.id))]
                wrongSessionResponse <- withPasskeyVerifiedUserAndCurrentVenue currentOwner currentVenue.id do
                    callActionWithParams BillingCancelAction
                        [ ("attempt_id", cs (inputValue currentAttempt.id))
                        , ("session_id", "cs_cancel_forged_123")
                        ]

                validResponse `responseStatusShouldBe` status200
                validResponse `responseBodyShouldContain` "Billing Cancelled"
                lookup "Location" (responseHeaders crossVenueResponse) `shouldBe` Just "http://localhost/Billing"
                lookup "Location" (responseHeaders wrongSessionResponse) `shouldBe` Just "http://localhost/Billing"
                unchangedAttempt <- fetch currentAttempt.id
                unchangedAttempt.status `shouldBe` "open"

        it "shows a pending Checkout modal on Billing while waiting for webhook confirmation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Pending Modal Venue"
                owner <- createUserRecord "billing-pending-modal-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                attempt <- createOpenBillingCheckoutAttempt venue owner "cs_test_123"

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestQuery (cs ("checkout=success&attempt_id=" <> inputValue attempt.id <> "&session_id=cs_test_123")) do
                        callAction BillingAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Finalising subscription"
                response `responseBodyShouldContain` "spinner-border"
                response `responseBodyShouldNotContain` "Checkout session:"
                response `responseBodyShouldNotContain` "cs_test_123"
                response `responseBodyShouldContain` "app-page-dialog-modal"
                response `responseBodyShouldNotContain` "data-billing-checkout-modal"
                response `responseBodyShouldNotContain` "data-billing-checkout-modal-backdrop"
                response `responseBodyShouldNotContain` "data-live-update-url="
                response `responseBodyShouldContain` (cs ("&quot;url&quot;:&quot;/ShowbillingStatusLiveFragment?checkout=success&amp;attempt_id=" <> inputValue attempt.id <> "&quot;"))
                response `responseBodyShouldNotContain` "&quot;mountState&quot;"

        it "does not render Checkout progress for uncorrelated direct query parameters" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Forged Return Query Venue"
                owner <- createUserRecord "billing-forged-return-query@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestQuery "checkout=success&attempt_id=00000000-0000-0000-0000-000000000001&session_id=cs_forged_123" do
                        callAction BillingAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "Finalising subscription"
                response `responseBodyShouldNotContain` "Subscription confirmed"
                response `responseBodyShouldNotContain` "Checkout session: cs_forged_123"

        it "handles malformed Checkout attempt ids at every return boundary" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Malformed Return Venue"
                owner <- createUserRecord "billing-malformed-return@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"

                successResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callActionWithParams BillingSuccessAction
                        [ ("attempt_id", "not-a-uuid")
                        , ("session_id", "cs_forged_123")
                        ]
                cancelResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callActionWithParams BillingCancelAction
                        [("attempt_id", "not-a-uuid")]
                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestQuery "checkout=success&attempt_id=not-a-uuid&session_id=cs_forged_123" do
                        callAction BillingAction
                fragmentResponse <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestQuery "checkout=success&attempt_id=not-a-uuid&session_id=cs_forged_123" do
                        callAction ShowbillingStatusLiveFragmentAction

                lookup "Location" (responseHeaders successResponse) `shouldBe` Just "http://localhost/Billing"
                lookup "Location" (responseHeaders cancelResponse) `shouldBe` Just "http://localhost/Billing"
                pageResponse `responseStatusShouldBe` status200
                fragmentResponse `responseStatusShouldBe` status200
                pageResponse `responseBodyShouldNotContain` "Finalising subscription"
                fragmentResponse `responseBodyShouldNotContain` "Finalising subscription"

        it "does not confirm an open attempt from an unrelated existing subscription" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Unrelated Subscription Return Venue"
                owner <- createUserRecord "billing-unrelated-subscription-return@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createVenueSubscriptionWithStatus venue "active"
                attempt <- createOpenBillingCheckoutAttempt venue owner "cs_pending_123"
                processedAt <- getCurrentTime
                _ <-
                    newRecord @BillingEvent
                        |> set #stripeEventId "evt_unrelated_checkout_123"
                        |> set #eventType "checkout.session.completed"
                        |> set #livemode False
                        |> set #providerObjectType (Just "checkout.session")
                        |> set #providerObjectId (Just "cs_other_attempt_123")
                        |> set #venueId (Just (unpackId venue.id))
                        |> set #stripeCustomerId (Just attempt.stripeCustomerId)
                        |> set #stripeSubscriptionId (Just "sub_active")
                        |> set #status "processed"
                        |> set #processedAt (Just processedAt)
                        |> createRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestQuery (cs ("checkout=success&attempt_id=" <> inputValue attempt.id <> "&session_id=cs_pending_123")) do
                        callAction ShowbillingStatusLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Finalising subscription"
                response `responseBodyShouldNotContain` "Subscription confirmed"

        it "confirms an exact processed Checkout webhook with its matching local subscription" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Confirmed Modal Venue"
                owner <- createUserRecord "billing-confirmed-modal-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <-
                    newRecord @VenueSubscription
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeSubscriptionId "sub_confirmed_123"
                        |> set #stripePriceId "price_monthly_123"
                        |> set #livemode False
                        |> set #status "active"
                        |> set #cancelAtPeriodEnd False
                        |> createRecord
                attempt <- createOpenBillingCheckoutAttempt venue owner "cs_test_123"
                processedAt <- getCurrentTime
                _ <-
                    newRecord @BillingEvent
                        |> set #stripeEventId "evt_checkout_confirmed_123"
                        |> set #eventType "checkout.session.completed"
                        |> set #livemode False
                        |> set #providerObjectType (Just "checkout.session")
                        |> set #providerObjectId (Just "cs_test_123")
                        |> set #venueId (Just (unpackId venue.id))
                        |> set #stripeCustomerId (Just attempt.stripeCustomerId)
                        |> set #stripeSubscriptionId (Just "sub_confirmed_123")
                        |> set #status "processed"
                        |> set #processedAt (Just processedAt)
                        |> createRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestQuery (cs ("checkout=success&attempt_id=" <> inputValue attempt.id <> "&session_id=cs_test_123")) do
                        callAction ShowbillingStatusLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Subscription confirmed"
                response `responseBodyShouldNotContain` "sub_confirmed_123"
                response `responseBodyShouldContain` "Continue"
                response `responseBodyShouldContain` "app-page-dialog-modal"
                response `responseBodyShouldNotContain` "data-billing-checkout-modal"

        it "renders the correlated attempt failure without trusting return parameters" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Failed Modal Venue"
                owner <- createUserRecord "billing-failed-modal-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                attempt <- createOpenBillingCheckoutAttempt venue owner "cs_test_123"
                    >>= updateRecord
                        . set #errorSummary (Just "processing failed")
                        . set #errorCode (Just "webhook_processing_failed")
                        . set #status "failed"

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestQuery (cs ("checkout=success&attempt_id=" <> inputValue attempt.id <> "&session_id=cs_test_123")) do
                        callAction ShowbillingStatusLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Subscription needs attention"
                response `responseBodyShouldContain` "We could not confirm this Checkout"
                response `responseBodyShouldNotContain` "processing failed"
                response `responseBodyShouldNotContain` "webhook_processing_failed"
                response `responseBodyShouldNotContain` (inputValue attempt.id)
                response `responseBodyShouldNotContain` "cs_test_123"
                response `responseBodyShouldContain` "Try Checkout Again"
                response `responseBodyShouldContain` "data-bepis-navigation-loading=\"true\""
                response `responseBodyShouldContain` "Opening Stripe"

withRequestQuery :: (?request :: Wai.Request) => ByteString -> ((?request :: Wai.Request) => IO result) -> IO result
withRequestQuery query callback = do
    let queryBytes = if "?" `ByteString.isPrefixOf` query then ByteString.drop 1 query else query
    let request' = ?request
            { Wai.rawQueryString = "?" <> queryBytes
            , Wai.queryString = URI.parseQuery queryBytes
            }
    let ?request = request'
    callback

createOpenBillingCheckoutAttempt :: (?modelContext :: ModelContext) => Venue -> User -> Text -> IO BillingCheckoutAttempt
createOpenBillingCheckoutAttempt venue owner sessionId =
    newRecord @BillingCheckoutAttempt
        |> set #venueId (unpackId venue.id)
        |> set #initiatedByUserId (unpackId owner.id)
        |> set #livemode False
        |> set #stripeCustomerId "cus_checkout_attempt"
        |> set #stripePriceId "price_monthly_123"
        |> set #stripeCheckoutSessionId (Just sessionId)
        |> set #status "open"
        |> createRecord

createVenueSubscriptionWithStatus :: (?modelContext :: ModelContext) => Venue -> Text -> IO VenueSubscription
createVenueSubscriptionWithStatus venue subscriptionStatus =
    newRecord @VenueSubscription
        |> set #venueId (unpackId venue.id)
        |> set #stripeSubscriptionId ("sub_" <> subscriptionStatus)
        |> set #stripePriceId "price_monthly_123"
        |> set #livemode False
        |> set #status subscriptionStatus
        |> set #cancelAtPeriodEnd False
        |> createRecord

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

validMonthlyPrice :: StripePrice
validMonthlyPrice =
    StripePrice
        { stripePriceId = "price_monthly_123"
        , stripePriceLivemode = False
        , active = True
        , currency = "aud"
        , unitAmount = Just 10000
        , priceType = "recurring"
        , recurring = Just StripeRecurring
            { interval = "month"
            , intervalCount = 1
            , usageType = Just "licensed"
            }
        }

checkoutStripeClient :: StripeClient
checkoutStripeClient =
    failingStripeClient
        { listPrices = \_ -> pure (Right [validMonthlyPrice])
        , createCustomer = \_ _ _ _ -> pure (Right StripeCustomer { stripeCustomerId = "cus_checkout_123", stripeCustomerLivemode = False })
        , createCheckoutSession = \_ attemptId venueId customerId priceId successUrl cancelUrl ->
            if customerId == "cus_checkout_123"
                    && priceId == "price_monthly_123"
                    && not (Text.null venueId)
                    && successUrl == "http://localhost/BillingSuccess?attempt_id=" <> attemptId <> "&session_id={CHECKOUT_SESSION_ID}"
                    && cancelUrl == "http://localhost/BillingCancel?attempt_id=" <> attemptId
                then pure (Right StripeCheckoutSession
                    { stripeCheckoutSessionId = "cs_checkout_123"
                    , stripeCheckoutSessionUrl = Just "https://checkout.stripe.com/c/pay/cs_test_123"
                    , stripeCheckoutCustomerId = Just customerId
                    , stripeCheckoutSubscriptionId = Nothing
                    , stripeCheckoutClientReferenceId = Nothing
                    , stripeCheckoutVenueId = Nothing
                    , stripeCheckoutLivemode = False
                    , stripeCheckoutMode = "subscription"
                    , stripeCheckoutStatus = "open"
                    , stripeCheckoutExpiresAt = 2000000000
                    })
                else pure (Left (StripeHttpError "unexpected checkout request"))
        }

checkoutStripeClientExpectingCustomer :: Text -> Text -> StripeClient
checkoutStripeClientExpectingCustomer expectedVenueName expectedOwnerEmail =
    checkoutStripeClient
        { createCustomer = \_ venueId venueName ownerEmail ->
            if venueName == expectedVenueName && ownerEmail == expectedOwnerEmail && not (Text.null venueId)
                then pure (Right StripeCustomer { stripeCustomerId = "cus_checkout_123", stripeCustomerLivemode = False })
                else pure (Left (StripeHttpError "unexpected customer request"))
        }

completedCheckoutStripeClient :: StripeClient
completedCheckoutStripeClient =
    failingStripeClient
        { retrieveCheckoutSession = \_ sessionId customerId ->
            pure (Right StripeCheckoutSession
                { stripeCheckoutSessionId = sessionId
                , stripeCheckoutSessionUrl = Nothing
                , stripeCheckoutCustomerId = Just customerId
                , stripeCheckoutSubscriptionId = Just "sub_completed_resume_123"
                , stripeCheckoutClientReferenceId = Nothing
                , stripeCheckoutVenueId = Nothing
                , stripeCheckoutLivemode = False
                , stripeCheckoutMode = "subscription"
                , stripeCheckoutStatus = "complete"
                , stripeCheckoutExpiresAt = 2000000000
                })
        }

resumableCheckoutStripeClient :: IORef.IORef Int -> IORef.IORef Int -> StripeClient
resumableCheckoutStripeClient createCalls retrieveCalls =
    checkoutStripeClient
        { createCheckoutSession = \config attemptId venueId customerId priceId successUrl cancelUrl -> do
            IORef.modifyIORef' createCalls (+ 1)
            checkoutStripeClient.createCheckoutSession config attemptId venueId customerId priceId successUrl cancelUrl
        , retrieveCheckoutSession = \_ sessionId customerId -> do
            IORef.modifyIORef' retrieveCalls (+ 1)
            pure (Right StripeCheckoutSession
                { stripeCheckoutSessionId = sessionId
                , stripeCheckoutSessionUrl = Just "https://checkout.stripe.com/c/pay/cs_test_123"
                , stripeCheckoutCustomerId = Just customerId
                , stripeCheckoutSubscriptionId = Nothing
                , stripeCheckoutClientReferenceId = Nothing
                , stripeCheckoutVenueId = Nothing
                , stripeCheckoutLivemode = False
                , stripeCheckoutMode = "subscription"
                , stripeCheckoutStatus = "open"
                , stripeCheckoutExpiresAt = 2000000000
                })
        }

retryingCheckoutStripeClient :: IORef.IORef [Text] -> StripeClient
retryingCheckoutStripeClient createAttempts =
    checkoutStripeClient
        { createCheckoutSession = \config attemptId venueId customerId priceId successUrl cancelUrl -> do
            attempts <- IORef.atomicModifyIORef' createAttempts \attempts ->
                let updatedAttempts = attemptId : attempts
                 in (updatedAttempts, updatedAttempts)
            case attempts of
                [_] -> pure (Left (StripeHttpError "simulated interrupted response"))
                _ -> checkoutStripeClient.createCheckoutSession config attemptId venueId customerId priceId successUrl cancelUrl
        }

crashingCheckoutStripeClient :: IORef.IORef [Text] -> StripeClient
crashingCheckoutStripeClient createAttempts =
    checkoutStripeClient
        { createCheckoutSession = \config attemptId venueId customerId priceId successUrl cancelUrl -> do
            attempts <- IORef.atomicModifyIORef' createAttempts \attempts ->
                let updatedAttempts = attemptId : attempts
                 in (updatedAttempts, updatedAttempts)
            case attempts of
                [_] -> Exception.throwIO (userError "simulated process interruption")
                _ -> checkoutStripeClient.createCheckoutSession config attemptId venueId customerId priceId successUrl cancelUrl
        }

expiringCheckoutStripeClient :: IORef.IORef [Text] -> StripeClient
expiringCheckoutStripeClient createAttemptIds =
    checkoutStripeClient
        { createCheckoutSession = \_ attemptId _ customerId _ _ _ -> do
            attemptIds <- IORef.atomicModifyIORef' createAttemptIds \attemptIds ->
                let updatedAttemptIds = attemptId : attemptIds
                 in (updatedAttemptIds, updatedAttemptIds)
            let sequenceNumber = length attemptIds
            pure (Right StripeCheckoutSession
                { stripeCheckoutSessionId = "cs_expiring_" <> tshow sequenceNumber
                , stripeCheckoutSessionUrl = Just ("https://checkout.stripe.com/c/pay/cs_expiring_" <> tshow sequenceNumber)
                , stripeCheckoutCustomerId = Just customerId
                , stripeCheckoutSubscriptionId = Nothing
                , stripeCheckoutClientReferenceId = Nothing
                , stripeCheckoutVenueId = Nothing
                , stripeCheckoutLivemode = False
                , stripeCheckoutMode = "subscription"
                , stripeCheckoutStatus = "open"
                , stripeCheckoutExpiresAt = 2000000000
                })
        , retrieveCheckoutSession = \_ sessionId customerId ->
            pure (Right StripeCheckoutSession
                { stripeCheckoutSessionId = sessionId
                , stripeCheckoutSessionUrl = Nothing
                , stripeCheckoutCustomerId = Just customerId
                , stripeCheckoutSubscriptionId = Nothing
                , stripeCheckoutClientReferenceId = Nothing
                , stripeCheckoutVenueId = Nothing
                , stripeCheckoutLivemode = False
                , stripeCheckoutMode = "subscription"
                , stripeCheckoutStatus = "expired"
                , stripeCheckoutExpiresAt = 1784678400
                })
        }

concurrentCheckoutStripeClient
    :: Concurrent.MVar ()
    -> Concurrent.MVar ()
    -> IORef.IORef Int
    -> IORef.IORef Int
    -> StripeClient
concurrentCheckoutStripeClient createEntered releaseCreate createCalls customerCalls =
    checkoutStripeClient
        { createCustomer = \config venueId venueName ownerEmail -> do
            IORef.atomicModifyIORef' customerCalls \count -> (count + 1, ())
            checkoutStripeClient.createCustomer config venueId venueName ownerEmail
        , createCheckoutSession = \config attemptId venueId customerId priceId successUrl cancelUrl -> do
            callNumber <- IORef.atomicModifyIORef' createCalls \count ->
                let updatedCount = count + 1
                 in (updatedCount, updatedCount)
            when (callNumber == 1) do
                Concurrent.putMVar createEntered ()
                Concurrent.takeMVar releaseCreate
            checkoutStripeClient.createCheckoutSession config attemptId venueId customerId priceId successUrl cancelUrl
        , retrieveCheckoutSession = \_ sessionId customerId ->
            pure (Right StripeCheckoutSession
                { stripeCheckoutSessionId = sessionId
                , stripeCheckoutSessionUrl = Just "https://checkout.stripe.com/c/pay/cs_test_123"
                , stripeCheckoutCustomerId = Just customerId
                , stripeCheckoutSubscriptionId = Nothing
                , stripeCheckoutClientReferenceId = Nothing
                , stripeCheckoutVenueId = Nothing
                , stripeCheckoutLivemode = False
                , stripeCheckoutMode = "subscription"
                , stripeCheckoutStatus = "open"
                , stripeCheckoutExpiresAt = 2000000000
                })
        }

unsafeCheckoutRedirectClient :: StripeClient
unsafeCheckoutRedirectClient =
    checkoutStripeClient
        { createCheckoutSession = \_ _ _ customerId _ _ _ ->
            pure (Right StripeCheckoutSession
                { stripeCheckoutSessionId = "cs_unsafe_redirect_123"
                , stripeCheckoutSessionUrl = Just "https://checkout.stripe.com.evil.example/session"
                , stripeCheckoutCustomerId = Just customerId
                , stripeCheckoutSubscriptionId = Nothing
                , stripeCheckoutClientReferenceId = Nothing
                , stripeCheckoutVenueId = Nothing
                , stripeCheckoutLivemode = False
                , stripeCheckoutMode = "subscription"
                , stripeCheckoutStatus = "open"
                , stripeCheckoutExpiresAt = 1784764800
                })
        }

checkoutAndPortalStripeClient :: StripeClient
checkoutAndPortalStripeClient =
    checkoutStripeClient
        { createPortalSession = portalStripeClient.createPortalSession
        }

portalStripeClient :: StripeClient
portalStripeClient =
    failingStripeClient
        { createPortalSession = \_ _ _ customerId returnUrl ->
            if customerId == "cus_portal_123" && returnUrl == "http://localhost/Billing"
                then pure (Right StripePortalSession
                    { stripePortalSessionId = "bps_portal_123"
                    , stripePortalSessionUrl = "https://billing.stripe.com/p/session/bps_test_123"
                    , stripePortalSessionLivemode = False
                    , stripePortalCustomerId = customerId
                    , stripePortalReturnUrl = returnUrl
                    })
                else pure (Left (StripeHttpError "unexpected portal request"))
        }

recordingPortalStripeClient :: IORef.IORef [Text] -> StripeClient
recordingPortalStripeClient requestIds =
    portalStripeClient
        { createPortalSession = \config requestId venueId customerId returnUrl -> do
            IORef.modifyIORef' requestIds (requestId :)
            portalStripeClient.createPortalSession config requestId venueId customerId returnUrl
        }

unsafePortalRedirectClient :: StripeClient
unsafePortalRedirectClient =
    failingStripeClient
        { createPortalSession = \_ _ _ customerId returnUrl ->
            pure (Right StripePortalSession
                { stripePortalSessionId = "bps_unsafe_redirect_123"
                , stripePortalSessionUrl = "https://billing.stripe.com.evil.example/session"
                , stripePortalSessionLivemode = False
                , stripePortalCustomerId = customerId
                , stripePortalReturnUrl = returnUrl
                })
        }

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

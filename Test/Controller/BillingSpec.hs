module Test.Controller.BillingSpec where

import Application.Billing.Stripe
import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import Config
import qualified Data.ByteString as ByteString
import Generated.Types
import IHP.ControllerPrelude
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

tests :: Spec
tests = beforeAll testContext do
    describe "BillingController" do
        it "redirects unauthenticated users from billing" $ withContext do
            response <- callAction BillingAction
            response `responseStatusShouldBe` status302

        it "shows billing to venue owners" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Owner Venue"
                owner <- createUserRecord "billing-owner-page@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callAction BillingAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Billing"
                response `responseBodyShouldContain` "data-bepis-surface=\"billing\""
                response `responseBodyShouldContain` "billing-status-fragment"
                response `responseBodyShouldContain` "billing:"
                response `responseBodyShouldContain` "AUD 100/month"
                response `responseBodyShouldContain` "Start Subscription"
                response `responseBodyShouldContain` "Manage Billing"
                response `responseBodyShouldNotContain` "Manual Controls"

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

        it "shows support-mode super admins the manual controls" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Support Venue"
                superAdmin <- createUserRecordWithPlatformRole "billing-support@example.com" "staff" (Just SuperAdminRole) True

                response <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    callAction BillingAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Manual Controls"
                response `responseBodyShouldContain` "Manual read-only"

        it "starts hosted Checkout and stores one Stripe Customer per venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Checkout Venue"
                owner <- createUserRecord "billing-checkout-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"

                response <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest checkoutStripeClient do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingCheckoutSessionAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "https://checkout.stripe.test/session"
                customer <- query @VenueBillingCustomer |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                customer.stripeCustomerId `shouldBe` "cus_checkout_123"

        it "redirects existing customers to Stripe Customer Portal" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Portal Venue"
                owner <- createUserRecord "billing-portal-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <-
                    newRecord @VenueBillingCustomer
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeCustomerId "cus_portal_123"
                        |> createRecord

                response <- withStripeConfigForTest (Right testStripeConfig) do
                    withStripeClientForTest portalStripeClient do
                        withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                            callAction CreateBillingPortalSessionAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "https://billing.stripe.test/session"

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

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callActionWithParams BillingSuccessAction [("session_id", "cs_test_123")]

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/Billing?checkout=success&session_id=cs_test_123"
                subscriptionCount <- query @VenueSubscription |> filterWhere (#venueId, unpackId venue.id) |> fetchCount
                subscriptionCount `shouldBe` 0

        it "shows a pending Checkout modal on Billing while waiting for webhook confirmation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Pending Modal Venue"
                owner <- createUserRecord "billing-pending-modal-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestQuery "checkout=success&session_id=cs_test_123" do
                        callAction BillingAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Finalising subscription"
                response `responseBodyShouldContain` "spinner-border"
                response `responseBodyShouldContain` "Checkout session: cs_test_123"
                response `responseBodyShouldContain` "app-page-dialog-modal"
                response `responseBodyShouldNotContain` "data-billing-checkout-modal"
                response `responseBodyShouldNotContain` "data-billing-checkout-modal-backdrop"
                response `responseBodyShouldNotContain` "data-live-update-url="
                response `responseBodyShouldContain` "&quot;url&quot;:&quot;/ShowbillingStatusLiveFragment?checkout=success&amp;session_id=cs_test_123&quot;"
                response `responseBodyShouldNotContain` "&quot;mountState&quot;"

        it "updates the Checkout modal to confirmed once the subscription webhook is processed" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Confirmed Modal Venue"
                owner <- createUserRecord "billing-confirmed-modal-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <-
                    newRecord @VenueSubscription
                        |> set #venueId (unpackId venue.id)
                        |> set #stripeSubscriptionId "sub_confirmed_123"
                        |> set #stripePriceId "price_monthly_123"
                        |> set #status "active"
                        |> set #cancelAtPeriodEnd False
                        |> createRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestQuery "checkout=success&session_id=cs_test_123" do
                        callAction ShowbillingStatusLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Subscription confirmed"
                response `responseBodyShouldContain` "sub_confirmed_123"
                response `responseBodyShouldContain` "Continue"
                response `responseBodyShouldContain` "app-page-dialog-modal"
                response `responseBodyShouldNotContain` "data-billing-checkout-modal"

        it "updates the Checkout modal to failed when a relevant webhook fails" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Failed Modal Venue"
                owner <- createUserRecord "billing-failed-modal-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <-
                    newRecord @BillingEvent
                        |> set #stripeEventId "evt_failed_checkout_123"
                        |> set #eventType "checkout.session.completed"
                        |> set #livemode False
                        |> set #providerObjectType (Just "checkout.session")
                        |> set #providerObjectId (Just "cs_test_123")
                        |> set #venueId (Just (unpackId venue.id))
                        |> set #status "failed"
                        |> set #errorSummary (Just "processing failed")
                        |> createRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    withRequestQuery "checkout=success&session_id=cs_test_123" do
                        callAction ShowbillingStatusLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Subscription needs attention"
                response `responseBodyShouldContain` "processing failed"
                response `responseBodyShouldContain` "Try Checkout Again"

withRequestQuery :: (?request :: Wai.Request) => ByteString -> ((?request :: Wai.Request) => IO result) -> IO result
withRequestQuery query callback = do
    let queryBytes = if "?" `ByteString.isPrefixOf` query then ByteString.drop 1 query else query
    let request' = ?request
            { Wai.rawQueryString = "?" <> queryBytes
            , Wai.queryString = URI.parseQuery queryBytes
            }
    let ?request = request'
    callback

testStripeConfig :: StripeConfig
testStripeConfig =
    StripeConfig
        { secretKey = "sk_test_redacted"
        , webhookSecret = "whsec_test_redacted"
        , priceLookupKey = Just defaultPriceLookupKey
        , priceId = Nothing
        , appBaseUrl = "http://localhost"
        }

validMonthlyPrice :: StripePrice
validMonthlyPrice =
    StripePrice
        { stripePriceId = "price_monthly_123"
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
        , createCustomer = \_ _ _ -> pure (Right StripeCustomer { stripeCustomerId = "cus_checkout_123" })
        , createCheckoutSession = \_ _ customerId priceId successUrl cancelUrl ->
            if customerId == "cus_checkout_123"
                    && priceId == "price_monthly_123"
                    && successUrl == "http://localhost/BillingSuccess?session_id={CHECKOUT_SESSION_ID}"
                    && cancelUrl == "http://localhost/BillingCancel"
                then pure (Right StripeCheckoutSession
                    { stripeCheckoutSessionId = "cs_checkout_123"
                    , stripeCheckoutSessionUrl = Just "https://checkout.stripe.test/session"
                    , stripeCheckoutCustomerId = Just customerId
                    , stripeCheckoutSubscriptionId = Nothing
                    })
                else pure (Left (StripeHttpError "unexpected checkout request"))
        }

portalStripeClient :: StripeClient
portalStripeClient =
    failingStripeClient
        { createPortalSession = \_ _ customerId returnUrl ->
            if customerId == "cus_portal_123" && returnUrl == "http://localhost/Billing"
                then pure (Right StripePortalSession
                    { stripePortalSessionId = "bps_portal_123"
                    , stripePortalSessionUrl = "https://billing.stripe.test/session"
                    })
                else pure (Left (StripeHttpError "unexpected portal request"))
        }

failingStripeClient :: StripeClient
failingStripeClient =
    StripeClient
        { listPrices = \_ -> pure (Left (StripeHttpError "unexpected listPrices"))
        , retrievePrice = \_ _ -> pure (Left (StripeHttpError "unexpected retrievePrice"))
        , createCustomer = \_ _ _ -> pure (Left (StripeHttpError "unexpected createCustomer"))
        , createCheckoutSession = \_ _ _ _ _ _ -> pure (Left (StripeHttpError "unexpected createCheckoutSession"))
        , retrieveCheckoutSession = \_ _ -> pure (Left (StripeHttpError "unexpected retrieveCheckoutSession"))
        , createPortalSession = \_ _ _ _ -> pure (Left (StripeHttpError "unexpected createPortalSession"))
        , retrieveSubscription = \_ _ -> pure (Left (StripeHttpError "unexpected retrieveSubscription"))
        }

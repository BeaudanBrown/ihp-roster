module Web.Billing.Mutations
    ( billingTouchedResources
    , startOrResumeBillingCheckoutMutation
    , updateVenueBillingControlMutation
    ) where

import Application.Billing.Checkout (CheckoutStartResult (..),
                                     startOrResumeCheckout)
import Application.Billing.Stripe (StripeClient, StripeConfig)
import Application.Helper.FrontendContract.Surface.Billing.Resource (billingResource)
import Application.Helper.SurfaceResource
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.SurfaceInvalidation (invalidateTouchedResources)

billingTouchedResources :: Id Venue -> [SurfaceResourceValue]
billingTouchedResources venueId =
    [billingResource (unpackId venueId)]

startOrResumeBillingCheckoutMutation
    :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request)
    => StripeClient
    -> StripeConfig
    -> Venue
    -> User
    -> (Id BillingCheckoutAttempt -> Text)
    -> (Id BillingCheckoutAttempt -> Text)
    -> IO (LiveMutationResult CheckoutStartResult)
startOrResumeBillingCheckoutMutation stripeClient stripeConfig venue owner successUrlFor cancelUrlFor = do
    result <- startOrResumeCheckout stripeClient stripeConfig venue owner successUrlFor cancelUrlFor
    forM_ result.checkoutCreatedCustomer \customer ->
        void $ recordCurrentUserAuditEvent
            BillingCustomerCreatedAudit
            "venue_billing_customers"
            (unpackId customer.id)
            (Aeson.object ["stripeCustomerId" Aeson..= customer.stripeCustomerId])
    invalidateTouchedResources "billing.checkout.start-or-resume" $
        liveMutationResult result (billingTouchedResources currentVenueId)

updateVenueBillingControlMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Bool -> Text -> UTCTime -> IO (LiveMutationResult VenueBillingControl)
updateVenueBillingControlMutation manualReadOnly reason now = do
    maybeControl <-
        query @VenueBillingControl
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchOneOrNothing
    control <- case maybeControl of
        Nothing ->
            newRecord @VenueBillingControl
                |> set #venueId (unpackId currentVenueId)
                |> set #manualReadOnly manualReadOnly
                |> set #manualReadOnlyReason normalizedReason
                |> set #setByUserId (Just (unpackId currentUser.id))
                |> set #setAt (Just now)
                |> createRecord
        Just existing ->
            existing
                |> set #manualReadOnly manualReadOnly
                |> set #manualReadOnlyReason (if manualReadOnly then Just reason else Nothing)
                |> set #setByUserId (Just (unpackId currentUser.id))
                |> set #setAt (Just now)
                |> updateRecord
    void $ recordCurrentUserAuditEvent
        VenueBillingControlUpdatedAudit
        "venue_billing_controls"
        (unpackId control.id)
        ( Aeson.object
            [ "manualReadOnly" Aeson..= control.manualReadOnly
            , "manualReadOnlyReason" Aeson..= control.manualReadOnlyReason
            ]
        )
    invalidateTouchedResources "billing.control.update" $
        liveMutationResult control (billingTouchedResources currentVenueId)
    where
        normalizedReason = if Text.null reason then Nothing else Just reason

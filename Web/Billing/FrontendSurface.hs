{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.Billing.FrontendSurface
    ( BillingCheckoutReturnState (..)
    , BillingScopeValue (..)
    , billingCandidateMountedFragments
    , billingSurfaceScope
    , billingSurfaceImpl
    , currentBillingScopeValue
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import qualified Application.Helper.FrontendContract.Surface.Billing as Surface
import qualified Application.Helper.FrontendContract.Surface.Billing.Live as SurfaceLive
import Application.Helper.FrontendContract.Surface.Live (SurfaceFragmentKey,
                                                         SurfaceScope,
                                                         surfaceScopeKey)
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.Url (appendQueryParams)
import qualified Data.UUID as UUID
import Web.Controller.Prelude

data BillingScopeValue = BillingScopeValue
    { billingVenueId :: !UUID.UUID
    }
    deriving (Eq, Show)

data BillingCheckoutReturnState = BillingCheckoutReturnState
    { billingCheckoutReturned  :: !Bool
    , billingCheckoutAttemptId :: !(Maybe Text)
    , billingCheckoutSessionId :: !(Maybe Text)
    }
    deriving (Eq, Show)


currentBillingScopeValue :: (?context :: ControllerContext) => BillingScopeValue
currentBillingScopeValue =
    BillingScopeValue { billingVenueId = currentVenueScopeId }

billingSurfaceImpl :: BillingScopeValue -> BillingCheckoutReturnState -> SurfaceImpl Surface.BillingSurface
billingSurfaceImpl scope checkoutReturnState =
    mkSurfaceImplFromValues @Surface.BillingSurface @Surface.BillingVenue
        "primary"
        (billingScopeFields scope)
        (billingMountStateFields checkoutReturnState)
        (billingCandidateMountedFragments checkoutReturnState)



billingSurfaceScope :: BillingScopeValue -> SurfaceScope
billingSurfaceScope scope =
    SurfaceLive.billingVenueLiveScope scope.billingVenueId

billingCandidateMountedFragments :: BillingCheckoutReturnState -> [FrontendSurfaceMountedFragment]
billingCandidateMountedFragments checkoutReturnState =
    [billingStatusMountedFragment (billingStatusFragmentUrl checkoutReturnState)]


billingScopeFields :: BillingScopeValue -> SurfaceFields (SurfaceScopeFieldSpecs Surface.BillingSurface Surface.BillingVenue)
billingScopeFields scope =
    surfaceField @Surface.VenueId scope.billingVenueId &: noSurfaceFields

billingMountStateFields :: BillingCheckoutReturnState -> SurfaceFields (SurfaceMountStateFieldSpecs Surface.BillingSurface)
billingMountStateFields checkoutReturnState =
    surfaceField @Surface.CheckoutReturned checkoutReturnState.billingCheckoutReturned
        &: surfaceField @Surface.CheckoutSessionId checkoutReturnState.billingCheckoutSessionId
        &: noSurfaceFields

billingStatusFragmentUrl :: BillingCheckoutReturnState -> Text
billingStatusFragmentUrl BillingCheckoutReturnState { billingCheckoutReturned = False } =
    pathTo ShowbillingStatusLiveFragmentAction
billingStatusFragmentUrl BillingCheckoutReturnState { billingCheckoutReturned = True, billingCheckoutAttemptId } =
    appendQueryParams (pathTo ShowbillingStatusLiveFragmentAction) $
        [("checkout", "success")]
            <> maybe [] (\attemptId -> [("attempt_id", attemptId)]) billingCheckoutAttemptId

billingStatusMountedFragment :: Text -> FrontendSurfaceMountedFragment
billingStatusMountedFragment statusUrl =
    frontendSurfaceMountedFragmentFor @Surface.BillingSurface @Surface.BillingStatus
        noSurfaceFields
        noSurfaceFields
        statusUrl
        FrontendSurfaceReplace

currentVenueScopeId :: (?context :: ControllerContext) => UUID.UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing    -> error "Billing live surface requires a current venue"

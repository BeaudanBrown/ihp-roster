{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.Billing.FrontendSurface
    ( BillingCheckoutReturnState (..)
    , BillingScopeValue (..)
    , billingCandidateMountedFragments
    , billingSurfaceScope
    , billingSurfaceImpl
    , billingSurfaceMountConfig
    , billingSurfaceScopeKey
    , billingSurfaceFragmentKeys
    , currentBillingCheckoutReturnState
    , currentBillingScopeValue
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import qualified Application.Helper.FrontendContract.Surface.Billing as Surface
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.Url (appendQueryParams)
import qualified Data.UUID as UUID
import qualified IHP.Prelude as Prelude
import Web.Controller.Prelude

data BillingScopeValue = BillingScopeValue
    { billingVenueId :: !UUID.UUID
    }
    deriving (Eq, Show)

data BillingCheckoutReturnState = BillingCheckoutReturnState
    { billingCheckoutReturned  :: !Bool
    , billingCheckoutSessionId :: !(Maybe Text)
    }
    deriving (Eq, Show)

currentBillingCheckoutReturnState :: BillingCheckoutReturnState
currentBillingCheckoutReturnState =
    BillingCheckoutReturnState
        { billingCheckoutReturned = False
        , billingCheckoutSessionId = Nothing
        }

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

billingSurfaceMountConfig :: BillingScopeValue -> BillingCheckoutReturnState -> FrontendSurfaceMountConfig
billingSurfaceMountConfig scope checkoutReturnState =
    (billingSurfaceImpl scope checkoutReturnState).surfaceImplMountConfig

billingSurfaceScopeKey :: BillingScopeValue -> Text
billingSurfaceScopeKey scope =
    frontendSurfaceScopeKeyFor @Surface.BillingSurface @Surface.BillingVenue (billingScopeFields scope)
        |> either (error . ("Typed Billing scope invariant failed: " <>)) Prelude.id

billingSurfaceScope :: BillingScopeValue -> SurfaceScope
billingSurfaceScope scope =
    billingLiveScope scope.billingVenueId

billingCandidateMountedFragments :: BillingCheckoutReturnState -> [FrontendSurfaceMountedFragment]
billingCandidateMountedFragments checkoutReturnState =
    [billingStatusMountedFragment (billingStatusFragmentUrl checkoutReturnState)]

billingSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
billingSurfaceFragmentKeys =
    frontendSurfaceMountedFragmentsToKeysFor @Surface.BillingSurface

billingScopeFields :: BillingScopeValue -> SurfaceFields (SurfaceScopeFieldSpecs Surface.BillingSurface Surface.BillingVenue)
billingScopeFields scope =
    surfaceField @Surface.VenueId scope.billingVenueId :& NoSurfaceFields

billingMountStateFields :: BillingCheckoutReturnState -> SurfaceFields (SurfaceMountStateFieldSpecs Surface.BillingSurface)
billingMountStateFields checkoutReturnState =
    surfaceField @Surface.CheckoutReturned checkoutReturnState.billingCheckoutReturned
        :& surfaceField @Surface.CheckoutSessionId checkoutReturnState.billingCheckoutSessionId
        :& NoSurfaceFields

billingStatusFragmentUrl :: BillingCheckoutReturnState -> Text
billingStatusFragmentUrl BillingCheckoutReturnState { billingCheckoutReturned = False } =
    pathTo ShowbillingStatusLiveFragmentAction
billingStatusFragmentUrl BillingCheckoutReturnState { billingCheckoutReturned = True, billingCheckoutSessionId } =
    appendQueryParams (pathTo ShowbillingStatusLiveFragmentAction) $
        ("checkout", "success") : maybe [] (\sessionId -> [("session_id", sessionId)]) billingCheckoutSessionId

billingStatusMountedFragment :: Text -> FrontendSurfaceMountedFragment
billingStatusMountedFragment statusUrl =
    frontendSurfaceMountedFragmentFor @Surface.BillingSurface @Surface.BillingStatus
        NoSurfaceFields
        "billing-status-fragment"
        statusUrl
        FrontendSurfaceReplace

currentVenueScopeId :: (?context :: ControllerContext) => UUID.UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing    -> error "Billing live surface requires a current venue"

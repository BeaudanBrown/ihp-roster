{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.Billing.Live
    ( billingLiveScope
    , billingStatusLiveFragment
    , matchBillingLiveScope
    ) where

import qualified Application.Helper.FrontendContract.Surface.Billing as Surface
import Application.Helper.FrontendContract.Surface.Live
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.UUID as UUID
import IHP.Prelude

billingLiveScope :: UUID.UUID -> SurfaceScope
billingLiveScope venueId =
    frontendSurfaceScope @Surface.BillingSurface @Surface.BillingVenue
        (surfaceField @Surface.VenueId venueId :& NoSurfaceFields)

matchBillingLiveScope :: SurfaceScope -> Maybe UUID.UUID
matchBillingLiveScope scope = do
    (venueId, ()) <-
        matchFrontendSurfaceScope @Surface.BillingSurface @Surface.BillingVenue scope
    pure venueId

billingStatusLiveFragment :: SurfaceFragmentKey
billingStatusLiveFragment = frontendSurfaceFragmentKey @Surface.BillingSurface @Surface.BillingStatus NoSurfaceFields

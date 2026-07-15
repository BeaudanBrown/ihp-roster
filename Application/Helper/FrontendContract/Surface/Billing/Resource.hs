{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.Billing.Resource
    ( billingResource
    ) where

import qualified Application.Helper.FrontendContract.Surface.Billing as Surface
import Application.Helper.FrontendContract.Surface.Resource
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.UUID as UUID
import IHP.Prelude

billingResource :: UUID.UUID -> SurfaceResourceValue
billingResource venueId =
    frontendSurfaceResource @Surface.BillingSurface @Surface.Billing
        (surfaceField @Surface.VenueId venueId :& NoSurfaceFields)

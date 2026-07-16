{-# LANGUAGE TypeFamilies #-}

-- | Typed generator ownership for Billing Surface adapters.
module Application.Helper.FrontendContract.Surface.Billing.HaskellAdapter
    ( BillingAdapterFamily
    ) where

import qualified Application.Helper.FrontendContract.Surface.Billing as Billing
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Association

data BillingAdapterFamily

instance SurfaceAdapterFamily BillingAdapterFamily where
    type AdapterFamilySurface BillingAdapterFamily = Billing.BillingSurface

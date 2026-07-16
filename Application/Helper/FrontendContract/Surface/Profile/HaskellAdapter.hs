{-# LANGUAGE TypeFamilies #-}

-- | Typed generator ownership for Profile and Staff Surface adapters.
module Application.Helper.FrontendContract.Surface.Profile.HaskellAdapter
    ( ProfileAdapterFamily
    , StaffAdapterFamily
    ) where

import Application.Helper.FrontendContract.Surface.HaskellAdapter.Association
import qualified Application.Helper.FrontendContract.Surface.Profile as Profile

data ProfileAdapterFamily
data StaffAdapterFamily

instance SurfaceAdapterFamily ProfileAdapterFamily where
    type AdapterFamilySurface ProfileAdapterFamily = Profile.ProfileSurface

instance SurfaceAdapterFamily StaffAdapterFamily where
    type AdapterFamilySurface StaffAdapterFamily = Profile.StaffSurface

{-# LANGUAGE TypeFamilies #-}

module Application.Helper.FrontendContract.Surface.SelfServiceLeave.HaskellAdapter
    ( SelfServiceLeaveAdapterFamily
    ) where

import Application.Helper.FrontendContract.Surface.HaskellAdapter.Association
import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave as SelfServiceLeave

data SelfServiceLeaveAdapterFamily

instance SurfaceAdapterFamily SelfServiceLeaveAdapterFamily where
    type AdapterFamilySurface SelfServiceLeaveAdapterFamily = SelfServiceLeave.SelfServiceLeaveSurface

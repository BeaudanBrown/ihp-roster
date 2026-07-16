{-# LANGUAGE TypeFamilies #-}

-- | Typed generator ownership for Support Surface adapters.
module Application.Helper.FrontendContract.Surface.Support.HaskellAdapter
    ( SupportAdapterFamily
    ) where

import Application.Helper.FrontendContract.Surface.HaskellAdapter.Association
import qualified Application.Helper.FrontendContract.Surface.Support as Support

data SupportAdapterFamily

instance SurfaceAdapterFamily SupportAdapterFamily where
    type AdapterFamilySurface SupportAdapterFamily = Support.SupportSurface

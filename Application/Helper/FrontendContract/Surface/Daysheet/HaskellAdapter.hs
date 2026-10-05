{-# LANGUAGE TypeFamilies #-}
module Application.Helper.FrontendContract.Surface.Daysheet.HaskellAdapter where

import Application.Helper.FrontendContract.Surface.HaskellAdapter.Association
import qualified Application.Helper.FrontendContract.Surface.Daysheet as Daysheet

data DaysheetAdapterFamily
instance SurfaceAdapterFamily DaysheetAdapterFamily where
    type AdapterFamilySurface DaysheetAdapterFamily = Daysheet.DaysheetSurface

{-# LANGUAGE TypeFamilies #-}
module Application.Helper.FrontendContract.Surface.DaysheetDesigner.HaskellAdapter where

import Application.Helper.FrontendContract.Surface.HaskellAdapter.Association
import qualified Application.Helper.FrontendContract.Surface.DaysheetDesigner as Designer

data DaysheetDesignerAdapterFamily
instance SurfaceAdapterFamily DaysheetDesignerAdapterFamily where
    type AdapterFamilySurface DaysheetDesignerAdapterFamily = Designer.DaysheetDesignerSurface

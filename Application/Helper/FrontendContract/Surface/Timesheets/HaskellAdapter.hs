{-# LANGUAGE TypeFamilies #-}

-- | Typed generator ownership for Timesheets Surface adapters.
module Application.Helper.FrontendContract.Surface.Timesheets.HaskellAdapter
    ( TimesheetsAdapterFamily
    ) where

import Application.Helper.FrontendContract.Surface.HaskellAdapter.Family
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets

data TimesheetsAdapterFamily

instance SurfaceAdapterFamily TimesheetsAdapterFamily where
    type AdapterFamilySurface TimesheetsAdapterFamily = Timesheets.TimesheetsSurface

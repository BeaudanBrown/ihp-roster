{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.Support.Resource
    ( supportAwardRatesResource
    , supportPublicHolidaysResource
    ) where

import Application.Helper.FrontendContract.Surface.Resource
import qualified Application.Helper.FrontendContract.Surface.Support as Surface
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

supportAwardRatesResource, supportPublicHolidaysResource :: SurfaceResourceValue
supportAwardRatesResource =
    frontendSurfaceResource @Surface.SupportSurface @Surface.SupportAwardRates NoSurfaceFields
supportPublicHolidaysResource =
    frontendSurfaceResource @Surface.SupportSurface @Surface.SupportPublicHolidays NoSurfaceFields

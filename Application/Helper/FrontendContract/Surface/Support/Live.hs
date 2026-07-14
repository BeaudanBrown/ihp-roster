{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.Support.Live
    ( matchSupportPlatformLiveScope
    , supportAwardRatesSectionLiveFragment
    , supportPlatformLiveScope
    , supportPublicHolidaysSectionLiveFragment
    ) where

import Application.Helper.FrontendContract.Surface.Live
import qualified Application.Helper.FrontendContract.Surface.Support as Surface
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

supportPlatformLiveScope :: SurfaceScope
supportPlatformLiveScope =
    frontendSurfaceScope @Surface.SupportSurface @Surface.SupportPlatform NoSurfaceFields

matchSupportPlatformLiveScope :: SurfaceScope -> Bool
matchSupportPlatformLiveScope scope =
    isJust (matchFrontendSurfaceScope @Surface.SupportSurface @Surface.SupportPlatform scope)

supportAwardRatesSectionLiveFragment, supportPublicHolidaysSectionLiveFragment :: SurfaceFragmentKey
supportAwardRatesSectionLiveFragment = frontendSurfaceFragmentKey @Surface.SupportSurface @Surface.SupportAwardRates NoSurfaceFields
supportPublicHolidaysSectionLiveFragment = frontendSurfaceFragmentKey @Surface.SupportSurface @Surface.SupportPublicHolidays NoSurfaceFields

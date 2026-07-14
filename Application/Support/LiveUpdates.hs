{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.Support.LiveUpdates
    ( SupportLiveFragment (..)
    , supportCandidateMountedFragments
    , supportLiveFragmentKey
    , supportSurface
    , supportSurfaceScope
    , supportSurfaceFragmentKeys
    ) where

import Application.Helper.FrontendContract.Surface.Live (SurfaceFragmentKey,
                                                         SurfaceScope)
import Application.Helper.FrontendContract.Surface.Runtime
import qualified Application.Helper.FrontendContract.Surface.Support as Surface
import qualified Application.Helper.FrontendContract.Surface.Support.Live as SurfaceLive
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

data SupportLiveFragment
    = SupportAwardRatesLiveFragment
    | SupportPublicHolidaysLiveFragment
    deriving (Eq, Show)

supportLiveFragmentKey :: SupportLiveFragment -> SurfaceFragmentKey
supportLiveFragmentKey = \case
    SupportAwardRatesLiveFragment -> SurfaceLive.supportAwardRatesSectionLiveFragment
    SupportPublicHolidaysLiveFragment -> SurfaceLive.supportPublicHolidaysSectionLiveFragment

supportSurfaceScope :: SurfaceScope
supportSurfaceScope = SurfaceLive.supportPlatformLiveScope

supportSurface :: SurfaceImpl Surface.SupportSurface
supportSurface =
    mkSurfaceImplFromValues @Surface.SupportSurface @Surface.SupportPlatform
        "primary"
        NoSurfaceFields
        NoSurfaceFields
        supportCandidateMountedFragments

supportCandidateMountedFragments :: [FrontendSurfaceMountedFragment]
supportCandidateMountedFragments =
    [ supportAwardRatesMountedFragment
    , supportPublicHolidaysMountedFragment
    ]

supportSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
supportSurfaceFragmentKeys = map (.mountedFragmentKey)

supportAwardRatesMountedFragment :: FrontendSurfaceMountedFragment
supportAwardRatesMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.SupportSurface @Surface.SupportAwardRates
        NoSurfaceFields
        NoSurfaceFields
        "/ShowFwcMapdAwardRatesSection"
        FrontendSurfaceReplace

supportPublicHolidaysMountedFragment :: FrontendSurfaceMountedFragment
supportPublicHolidaysMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.SupportSurface @Surface.SupportPublicHolidays
        NoSurfaceFields
        NoSurfaceFields
        "/ShowPublicHolidaysSection"
        FrontendSurfaceReplace

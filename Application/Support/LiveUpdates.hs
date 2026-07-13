{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.Support.LiveUpdates
    ( SupportLiveFragment (..)
    , supportCandidateMountedFragments
    , supportSurface
    , supportSurfaceScope
    , supportSurfaceFragmentKeys
    ) where

import Application.Helper.FrontendContract.Surface.Runtime
import qualified Application.Helper.FrontendContract.Surface.Support as Surface
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.LiveUpdate
import Application.Helper.LiveUpdate.Runtime
import IHP.Prelude

data SupportLiveFragment
    = SupportAwardRatesLiveFragment
    | SupportPublicHolidaysLiveFragment
    deriving (Eq, Show)

supportSurfaceScope :: SurfaceScope
supportSurfaceScope = supportPlatformLiveScope

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
supportSurfaceFragmentKeys =
    frontendSurfaceMountedFragmentsToKeysFor @Surface.SupportSurface

supportAwardRatesMountedFragment :: FrontendSurfaceMountedFragment
supportAwardRatesMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.SupportSurface @Surface.SupportAwardRates
        NoSurfaceFields
        "support-award-rates"
        "/ShowFwcMapdAwardRatesSection"
        FrontendSurfaceReplace

supportPublicHolidaysMountedFragment :: FrontendSurfaceMountedFragment
supportPublicHolidaysMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.SupportSurface @Surface.SupportPublicHolidays
        NoSurfaceFields
        "support-public-holidays"
        "/ShowPublicHolidaysSection"
        FrontendSurfaceReplace

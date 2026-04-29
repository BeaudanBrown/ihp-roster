module Application.Support.LiveUpdates
    ( supportAwardRatesSectionFragmentRef
    , supportLiveSurface
    , supportLiveSurfaceDefinition
    , supportLiveFragmentRefs
    , supportLiveUpdateScope
    , supportPublicHolidaysSectionFragmentRef
    ) where

import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate
import IHP.Prelude

data SupportLiveFragment
    = SupportAwardRatesLiveFragment
    | SupportPublicHolidaysLiveFragment

supportLiveUpdateScope :: LiveUpdateScope
supportLiveUpdateScope = SupportPlatformScope

supportLiveSurfaceDefinition :: LiveSurfaceDefinition () SupportLiveFragment
supportLiveSurfaceDefinition =
    LiveSurfaceDefinition
        { surfaceFeature = "support"
        , surfaceScope = const supportLiveUpdateScope
        , surfaceDefaultFragments = const supportLiveFragmentRefs
        , surfaceFragmentRef = const supportLiveFragmentRef
        , surfaceDecorateRequestsWithin =
            const
                [ "#support-shell"
                , "#support-award-rates-section"
                , "#support-public-holidays-section"
                ]
        }

supportLiveFragmentRefs :: [SupportLiveFragment]
supportLiveFragmentRefs =
    [ SupportAwardRatesLiveFragment
    , SupportPublicHolidaysLiveFragment
    ]

supportLiveFragmentRef :: SupportLiveFragment -> LiveFragmentRef
supportLiveFragmentRef SupportAwardRatesLiveFragment =
    mkLiveFragmentRef
        SupportAwardRatesSectionFragment
        "support-award-rates-section"
        "/ShowFwcMapdAwardRatesSection"
supportLiveFragmentRef SupportPublicHolidaysLiveFragment =
    mkLiveFragmentRef
        SupportPublicHolidaysSectionFragment
        "support-public-holidays-section"
        "/ShowPublicHolidaysSection"

supportAwardRatesSectionFragmentRef :: LiveFragmentRef
supportAwardRatesSectionFragmentRef =
    supportLiveFragmentRef SupportAwardRatesLiveFragment

supportPublicHolidaysSectionFragmentRef :: LiveFragmentRef
supportPublicHolidaysSectionFragmentRef =
    supportLiveFragmentRef SupportPublicHolidaysLiveFragment

supportLiveSurface :: LiveSurfaceConfig
supportLiveSurface =
    mkDefinedLiveSurface supportLiveSurfaceDefinition ()

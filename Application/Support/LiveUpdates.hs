module Application.Support.LiveUpdates
    ( SupportLiveFragment (..)
    , supportAwardRatesSectionFragmentRef
    , supportLiveSurface
    , supportLiveSurfaceDefinition
    , supportLiveFragmentRefs
    , supportLiveUpdateScope
    , supportPublicHolidaysSectionFragmentRef
    ) where

import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate
import IHP.Prelude

data SupportSurface

data SupportLiveFragment
    = SupportAwardRatesLiveFragment
    | SupportPublicHolidaysLiveFragment

supportLiveUpdateScope :: LiveUpdateScope
supportLiveUpdateScope = SupportPlatformScope

supportLiveSurfaceDefinition :: TypedLiveSurfaceDefinition SupportSurface () SupportLiveFragment
supportLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "support"
        , typedSurfaceScope = const (SurfaceScope supportLiveUpdateScope)
        , typedSurfaceScopeFromWire = \case
            SupportPlatformScope -> Just ()
            _ -> Nothing
        , typedSurfaceDefaultFragments = const supportLiveFragmentRefs
        , typedSurfaceFragmentRef = const (SurfaceFragmentRef . supportLiveFragmentRef)
        , typedSurfaceDecorateRequestsWithin =
            const
                [ "#support-shell"
                , "#support-award-rates-section"
                , "#support-public-holidays-section"
                ]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByScope (const (SurfaceScope supportLiveUpdateScope))
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
    mkTypedDefinedLiveSurface supportLiveSurfaceDefinition ()

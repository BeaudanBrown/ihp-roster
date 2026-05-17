module Application.Support.LiveUpdates
    ( SupportLiveFragment (..)
    , SupportSurface
    , supportLiveSurface
    , supportLiveSurfaceDefinition
    , supportLiveFragmentRefs
    , supportLiveUpdateScope
    ) where

import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate
import IHP.Prelude

data SupportSurface

data SupportLiveFragment
    = SupportAwardRatesLiveFragment
    | SupportPublicHolidaysLiveFragment
    deriving (Eq, Show)

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
        , typedSurfaceFragmentRef = const supportLiveFragmentRef
        , typedSurfaceDecorateRequestsWithin =
            const
                [ "#support-shell"
                , "#support-award-rates-section"
                , "#support-public-holidays-section"
                ]
        , typedSurfaceDependsOn = \_ fragment ->
            case fragment of
                SupportAwardRatesLiveFragment -> [SupportAwardRatesResource]
                SupportPublicHolidaysLiveFragment -> [SupportPublicHolidaysResource]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (const RequireSupportSuperAdmin)
        }

supportLiveFragmentRefs :: [SupportLiveFragment]
supportLiveFragmentRefs =
    [ SupportAwardRatesLiveFragment
    , SupportPublicHolidaysLiveFragment
    ]

supportLiveFragmentRef :: SupportLiveFragment -> SurfaceFragmentRef SupportSurface
supportLiveFragmentRef SupportAwardRatesLiveFragment =
    mkSurfaceFragmentRef
        SupportAwardRatesSectionFragment
        "support-award-rates-section"
        "/ShowFwcMapdAwardRatesSection"
supportLiveFragmentRef SupportPublicHolidaysLiveFragment =
    mkSurfaceFragmentRef
        SupportPublicHolidaysSectionFragment
        "support-public-holidays-section"
        "/ShowPublicHolidaysSection"

supportLiveSurface :: LiveSurfaceConfig
supportLiveSurface =
    mkTypedDefinedLiveSurface supportLiveSurfaceDefinition ()

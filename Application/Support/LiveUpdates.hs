{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

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

supportLiveSurfaceDefinition :: TypedLiveSurfaceDefinition SupportSurface () SupportLiveFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
supportLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "support"
        , typedSurfaceScope = const (SurfaceScope supportLiveUpdateScope)
        , typedSurfaceScopeFromWire = \case
            SupportPlatformScope -> Just ()
            _ -> Nothing
        , typedSurfaceDefaultFragments = const supportLiveFragmentRefs
        , typedSurfaceFragmentContract = \() fragment ->
            mkSurfaceFragmentContract
                (supportLiveFragmentRef fragment)
                (supportLiveFragmentDependencies fragment)
        , typedSurfaceDecorateRequestsWithin =
            const
                [ "#support-shell"
                , "#support-award-rates-section"
                , "#support-public-holidays-section"
                ]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (const RequireSupportSuperAdmin)
        , typedSurfaceInteractionSchema = emptyInteractionStaticSchema
        , typedSurfaceInteraction = const emptyInteractionCapability
        }

supportLiveFragmentRefs :: [SupportLiveFragment]
supportLiveFragmentRefs =
    [ SupportAwardRatesLiveFragment
    , SupportPublicHolidaysLiveFragment
    ]

supportLiveFragmentDependencies :: SupportLiveFragment -> FragmentDependencies
supportLiveFragmentDependencies SupportAwardRatesLiveFragment =
    liveFragmentDependsOn SupportAwardRatesResource []
supportLiveFragmentDependencies SupportPublicHolidaysLiveFragment =
    liveFragmentDependsOn SupportPublicHolidaysResource []

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

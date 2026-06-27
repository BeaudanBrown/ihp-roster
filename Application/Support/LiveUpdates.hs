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
    descriptorToTypedLiveSurfaceDefinition
        ( liveSurfaceDescriptor
            "support"
            (const (SurfaceScope supportLiveUpdateScope))
            (\case
                SupportPlatformScope -> Just ()
                _ -> Nothing)
            (liveSurfaceAuthorizationByRequirement (const RequireSupportSuperAdmin))
            ( map
                (\fragment ->
                    liveFragmentDescriptor
                        fragment
                        (const (supportLiveFragmentRef fragment))
                        (const (supportLiveFragmentDependencies fragment)))
                supportLiveFragmentRefs
            )
            |> liveSurfaceDescriptorWithDecorateRequestsWithin
                ( const
                    [ "#support-shell"
                    , "#support-award-rates-section"
                    , "#support-public-holidays-section"
                    ]
                )
        )

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

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
            (map supportLiveFragmentDescriptor supportLiveFragmentRefs)
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

supportLiveFragmentDescriptor :: SupportLiveFragment -> LiveFragmentDescriptor SupportSurface () SupportLiveFragment
supportLiveFragmentDescriptor SupportAwardRatesLiveFragment =
    staticLiveFragmentDescriptor
        SupportAwardRatesLiveFragment
        SupportAwardRatesSectionFragment
        "support-award-rates-section"
        "/ShowFwcMapdAwardRatesSection"
        (const (liveFragmentDependsOn SupportAwardRatesResource []))
supportLiveFragmentDescriptor SupportPublicHolidaysLiveFragment =
    staticLiveFragmentDescriptor
        SupportPublicHolidaysLiveFragment
        SupportPublicHolidaysSectionFragment
        "support-public-holidays-section"
        "/ShowPublicHolidaysSection"
        (const (liveFragmentDependsOn SupportPublicHolidaysResource []))

supportLiveSurface :: LiveSurfaceConfig
supportLiveSurface =
    mkTypedDefinedLiveSurface supportLiveSurfaceDefinition ()

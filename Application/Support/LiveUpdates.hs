module Application.Support.LiveUpdates
    ( supportAwardRatesSectionFragmentRef
    , supportLiveSurface
    , supportLiveUpdateScope
    , supportPublicHolidaysSectionFragmentRef
    ) where

import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate
import IHP.Prelude

supportLiveUpdateScope :: LiveUpdateScope
supportLiveUpdateScope = SupportPlatformScope

supportAwardRatesSectionFragmentRef :: LiveFragmentRef
supportAwardRatesSectionFragmentRef =
    mkLiveFragmentRef
        SupportAwardRatesSectionFragment
        "support-award-rates-section"
        "/ShowFwcMapdAwardRatesSection"

supportPublicHolidaysSectionFragmentRef :: LiveFragmentRef
supportPublicHolidaysSectionFragmentRef =
    mkLiveFragmentRef
        SupportPublicHolidaysSectionFragment
        "support-public-holidays-section"
        "/ShowPublicHolidaysSection"

supportLiveSurface :: LiveSurfaceConfig
supportLiveSurface =
    (mkLiveSurface
        "support"
        supportLiveUpdateScope
        [ supportAwardRatesSectionFragmentRef
        , supportPublicHolidaysSectionFragmentRef
        ])
        { decorateRequestsWithin =
            [ "#support-shell"
            , "#support-award-rates-section"
            , "#support-public-holidays-section"
            ]
        }

module Application.Support.LiveUpdates
    ( supportAwardRatesSectionFragmentRef
    , supportLiveSurface
    , supportLiveUpdateScope
    , supportPublicHolidaysSectionFragmentRef
    ) where

import Application.Helper.LiveUpdate
import Application.Helper.LiveSurface
import IHP.Prelude

supportLiveUpdateScope :: LiveUpdateScope
supportLiveUpdateScope = SupportPlatformScope

supportAwardRatesSectionFragmentRef :: LiveFragmentRef
supportAwardRatesSectionFragmentRef =
    LiveFragmentRef
        { fragmentKey = SupportAwardRatesSectionFragment
        , targetId = "support-award-rates-section"
        , url = "/ShowFwcMapdAwardRatesSection"
        , deferUntilBlur = False
        , protectionPolicy = NoProtection
        }

supportPublicHolidaysSectionFragmentRef :: LiveFragmentRef
supportPublicHolidaysSectionFragmentRef =
    LiveFragmentRef
        { fragmentKey = SupportPublicHolidaysSectionFragment
        , targetId = "support-public-holidays-section"
        , url = "/ShowPublicHolidaysSection"
        , deferUntilBlur = False
        , protectionPolicy = NoProtection
        }

supportLiveSurface :: LiveSurfaceConfig
supportLiveSurface =
    (mkLiveSurface
        "support"
        supportLiveUpdateScope
        [ supportAwardRatesSectionFragmentRef
        , supportPublicHolidaysSectionFragmentRef
        ])
        { decorateRequestsWithin =
            [ "[data-live-update-feature=\"support\"]"
            , "#support-award-rates-section"
            , "#support-public-holidays-section"
            ]
        }

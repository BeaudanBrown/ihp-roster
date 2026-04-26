module Application.Support.LiveUpdates
    ( supportAwardRatesSectionFragmentRef
    , supportLiveUpdateScope
    , supportPublicHolidaysSectionFragmentRef
    ) where

import Application.Helper.LiveUpdate
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

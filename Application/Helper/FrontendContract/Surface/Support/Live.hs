module Application.Helper.FrontendContract.Surface.Support.Live
    ( matchSupportPlatformLiveScope
    , supportAwardRatesLiveFragment
    , supportPlatformLiveScope
    , supportPublicHolidaysLiveFragment
    ) where

import Application.Helper.FrontendContract.Surface.Live (SurfaceScope)
import Application.Helper.FrontendContract.Surface.Support.Generated.Live (supportAwardRatesLiveFragment,
                                                                           supportPlatformLiveScope,
                                                                           supportPublicHolidaysLiveFragment)
import qualified Application.Helper.FrontendContract.Surface.Support.Generated.Live as Generated
import IHP.Prelude

-- | Recognize the platform-wide support scope without exposing field tuples.
matchSupportPlatformLiveScope :: SurfaceScope -> Bool
matchSupportPlatformLiveScope scope =
    isJust (Generated.matchSupportPlatformLiveScope scope)

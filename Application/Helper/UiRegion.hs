module Application.Helper.UiRegion
    ( UiRegionDomAttributes (..)
    , UiRegionLifecycleEvent (..)
    , UiRegionTransitionProfile (..)
    , canonicalUiRegionDomAttributes
    , canonicalUiRegionLifecycleEvents
    , uiRegionFragmentEnabledValue
    , uiRegionLifecycleEventName
    , uiRegionTransitionProfileText
    ) where

import IHP.Prelude

-- | Canonical browser-visible data attributes for server-declared Bepis UI
-- regions. Haskell helpers own these names; TypeScript consumes the generated
-- constants instead of inventing data-bepis-* strings.
data UiRegionDomAttributes = UiRegionDomAttributes
    { uiRegionFragmentAttribute     :: !Text
    , uiRegionLazySurfaceAttribute  :: !Text
    , uiRegionLazyFragmentAttribute :: !Text
    , uiRegionLazyRetryAttribute    :: !Text
    , uiRegionTransitionAttribute   :: !Text
    }
    deriving (Eq, Show)

data UiRegionTransitionProfile
    = UiRegionTransitionNone
    | UiRegionTransitionFade
    | UiRegionTransitionFadeSlide
    | UiRegionTransitionPanel
    deriving (Eq, Show)

data UiRegionLifecycleEvent
    = UiRegionRequestStart
    | UiRegionBeforeSwap
    | UiRegionAfterSwap
    | UiRegionSettle
    | UiRegionError
    deriving (Eq, Show)

canonicalUiRegionDomAttributes :: UiRegionDomAttributes
canonicalUiRegionDomAttributes =
    UiRegionDomAttributes
        { uiRegionFragmentAttribute = "data-bepis-fragment"
        , uiRegionLazySurfaceAttribute = "data-bepis-lazy-surface"
        , uiRegionLazyFragmentAttribute = "data-bepis-lazy-fragment"
        , uiRegionLazyRetryAttribute = "data-bepis-lazy-retry"
        , uiRegionTransitionAttribute = "data-bepis-region-transition"
        }

uiRegionFragmentEnabledValue :: Text
uiRegionFragmentEnabledValue = "true"

uiRegionTransitionProfileText :: UiRegionTransitionProfile -> Text
uiRegionTransitionProfileText = \case
    UiRegionTransitionNone -> "none"
    UiRegionTransitionFade -> "fade"
    UiRegionTransitionFadeSlide -> "fade-slide"
    UiRegionTransitionPanel -> "panel"

canonicalUiRegionLifecycleEvents :: [(UiRegionLifecycleEvent, Text)]
canonicalUiRegionLifecycleEvents =
    [ (UiRegionRequestStart, "bepis:region-request-start")
    , (UiRegionBeforeSwap, "bepis:region-before-swap")
    , (UiRegionAfterSwap, "bepis:region-after-swap")
    , (UiRegionSettle, "bepis:region-settle")
    , (UiRegionError, "bepis:region-error")
    ]

uiRegionLifecycleEventName :: UiRegionLifecycleEvent -> Text
uiRegionLifecycleEventName event =
    fromMaybe (error "Unknown UI region lifecycle event") (lookup event canonicalUiRegionLifecycleEvents)

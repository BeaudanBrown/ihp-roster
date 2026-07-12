{-# LANGUAGE TypeApplications #-}

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

import qualified Application.Helper.FrontendContract.UiRegion as Contract
import Application.Helper.FrontendContract.Values
import GHC.Generics (Generic)
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
    deriving (Eq, Show, Generic)

data UiRegionTransitionProfile
    = UiRegionTransitionNone
    | UiRegionTransitionFade
    | UiRegionTransitionFadeSlide
    | UiRegionTransitionPanel
    deriving (Eq, Show, Generic)

data UiRegionLifecycleEvent
    = UiRegionRequestStart
    | UiRegionBeforeSwap
    | UiRegionAfterSwap
    | UiRegionSettle
    | UiRegionError
    deriving (Eq, Show, Generic)

canonicalUiRegionDomAttributes :: UiRegionDomAttributes
canonicalUiRegionDomAttributes =
    UiRegionDomAttributes
        { uiRegionFragmentAttribute = domAttrValue @Contract.Fragment
        , uiRegionLazySurfaceAttribute = domAttrValue @Contract.LazySurface
        , uiRegionLazyFragmentAttribute = domAttrValue @Contract.LazyFragment
        , uiRegionLazyRetryAttribute = domAttrValue @Contract.LazyRetry
        , uiRegionTransitionAttribute = domAttrValue @Contract.RegionTransition
        }

uiRegionFragmentEnabledValue :: Text
uiRegionFragmentEnabledValue = "true"

uiRegionTransitionProfileText :: UiRegionTransitionProfile -> Text
uiRegionTransitionProfileText = \case
    UiRegionTransitionNone -> enumLiteralValue @Contract.UiRegionTransitionProfile @Contract.None
    UiRegionTransitionFade -> enumLiteralValue @Contract.UiRegionTransitionProfile @Contract.Fade
    UiRegionTransitionFadeSlide -> enumLiteralValue @Contract.UiRegionTransitionProfile @Contract.FadeSlide
    UiRegionTransitionPanel -> enumLiteralValue @Contract.UiRegionTransitionProfile @Contract.Panel

canonicalUiRegionLifecycleEvents :: [(UiRegionLifecycleEvent, Text)]
canonicalUiRegionLifecycleEvents =
    [ (UiRegionRequestStart, eventNameValue @Contract.RegionRequestStart)
    , (UiRegionBeforeSwap, eventNameValue @Contract.RegionBeforeSwap)
    , (UiRegionAfterSwap, eventNameValue @Contract.RegionAfterSwap)
    , (UiRegionSettle, eventNameValue @Contract.RegionSettle)
    , (UiRegionError, eventNameValue @Contract.RegionError)
    ]

uiRegionLifecycleEventName :: UiRegionLifecycleEvent -> Text
uiRegionLifecycleEventName event =
    fromMaybe (error "Unknown UI region lifecycle event") (lookup event canonicalUiRegionLifecycleEvents)

{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.UiRegion
    ( UiRegionContract
    , UiRegion
    , UiRegionTransitionProfile
    , None
    , Fade
    , FadeSlide
    , Panel
    , UiRegionLifecycleEvent
    , RequestStart
    , BeforeSwap
    , AfterSwap
    , Settle
    , Error
    , RegionRequestStart
    , RegionBeforeSwap
    , RegionAfterSwap
    , RegionSettle
    , RegionError
    , Fragment
    , LazySurface
    , LazyFragment
    , LazyRetry
    , RegionTransition
    ) where

import Application.Helper.FrontendContract.DSL hiding (Fragment)

data UiRegion

data UiRegionTransitionProfile
data None
data Fade
data FadeSlide
data Panel

data UiRegionLifecycleEvent
data RequestStart
data BeforeSwap
data AfterSwap
data Settle
data Error

data RegionRequestStart
data RegionBeforeSwap
data RegionAfterSwap
data RegionSettle
data RegionError

data Fragment
data LazySurface
data LazyFragment
data LazyRetry
data RegionTransition

type UiRegionContract =
    Global UiRegion
        '[ BrowserGuardSchema (Enum UiRegionTransitionProfile '[None, Fade, FadeSlide, Panel])
         , BrowserGuardSchema (Enum UiRegionLifecycleEvent '[RequestStart, BeforeSwap, AfterSwap, Settle, Error])
         , Event RegionRequestStart '[]
         , Event RegionBeforeSwap '[]
         , Event RegionAfterSwap '[]
         , Event RegionSettle '[]
         , Event RegionError '[]
         , DomAttr Fragment
         , DomAttr LazySurface
         , ServerDomAttr LazyFragment
         , DomAttr LazyRetry
         , DomAttr RegionTransition
         ]

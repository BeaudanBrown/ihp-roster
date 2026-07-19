{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.HorizontalScroll
    ( HorizontalScrollContract
    , HorizontalScroll
    , HorizontalSnapMode
    , EqualGroups
    , NearestItem
    , HorizontalSnapConfig
    , SnapMode
    , ItemSelector
    , GroupCount
    , GroupProperty
    , GroupScopeSelector
    , HorizontalDragConfig
    , IgnoreSelector
    , HorizontalScrollSnap
    , HorizontalScrollDrag
    ) where

import Application.Helper.FrontendContract.DSL

-- | Reusable horizontal drag and snap presentation vocabulary. Haskell owns
-- the mode and DOM relationships; pointer thresholds, scheduling, and
-- transient state remain private to the browser adapter.
data HorizontalScroll

data HorizontalSnapMode
data EqualGroups
data NearestItem

data HorizontalSnapConfig
data SnapMode
data ItemSelector
data GroupCount
data GroupProperty
data GroupScopeSelector

data HorizontalDragConfig
data IgnoreSelector

data HorizontalScrollSnap
data HorizontalScrollDrag

type HorizontalScrollContract =
    Global HorizontalScroll
        '[ BrowserGuardSchema (Enum HorizontalSnapMode '[EqualGroups, NearestItem])
         , BrowserInboundSchema (Record HorizontalSnapConfig
            '[ Field SnapMode ('WireRef HorizontalSnapMode)
             , NullableField ItemSelector 'WireText
             , NullableField GroupCount 'WireInt
             , NullableField GroupProperty 'WireText
             , NullableField GroupScopeSelector 'WireText
             ])
         , BrowserInboundSchema (Record HorizontalDragConfig
            '[ NullableField IgnoreSelector 'WireText
             ])
         , DomAttr HorizontalScrollSnap
         , DomAttr HorizontalSnapConfig
         , DomAttr HorizontalScrollDrag
         , DomAttr HorizontalDragConfig
         ]

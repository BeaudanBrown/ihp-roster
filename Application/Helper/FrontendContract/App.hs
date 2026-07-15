{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.App
    ( AppContract
    , App
    , RosterStaffSortKey
    , Name
    , Role
    , Shifts
    , PageReady
    , LiveFragmentsRefresh
    , Scope
    , ScopeKey
    , Fragments
    , InteractionIntent
    , IntentSubmit
    , InteractionSessionStart
    , InteractionSessionEnd
    , InteractionSessionCancelRequest
    , DialogOverlayMount
    , ToastOverlayMount
    , HtmxActionMethod
    , HtmxGet
    , HtmxPost
    , HtmxPut
    , HtmxPatch
    , HtmxDelete
    , HtmxActionSwap
    , HtmxInnerHTML
    , HtmxOuterHTML
    , HtmxBeforeEnd
    , HtmxAfterBegin
    , HtmxNoneSwap
    , HtmxOuterHTMLDashed
    ) where

import Application.Helper.FrontendContract.DSL

data App

data RosterStaffSortKey
data Name
data Role
data Shifts

data PageReady
data LiveFragmentsRefresh
data Scope
data ScopeKey
data Fragments
data InteractionIntent
data IntentSubmit
data InteractionSessionStart
data InteractionSessionEnd
data InteractionSessionCancelRequest

data DialogOverlayMount
data ToastOverlayMount

data HtmxActionMethod
data HtmxGet
data HtmxPost
data HtmxPut
data HtmxPatch
data HtmxDelete

data HtmxActionSwap
data HtmxInnerHTML
data HtmxOuterHTML
data HtmxBeforeEnd
data HtmxAfterBegin
data HtmxNoneSwap
data HtmxOuterHTMLDashed

type AppContract =
    Global App
        '[ BrowserGuardSchema (Enum RosterStaffSortKey '[Name, Role, Shifts])
         , Event PageReady '[]
         , InboundEvent LiveFragmentsRefresh
            '[ Field Scope 'WireSurfaceScope
             , Field ScopeKey 'WireText
             , Field Fragments ('WireList 'WireSurfaceFragmentKey)
             ]
         , Event InteractionIntent '[]
         , ServerEvent IntentSubmit '[]
         , Event InteractionSessionStart '[]
         , Event InteractionSessionEnd '[]
         , Event InteractionSessionCancelRequest '[]
         , DomId DialogOverlayMount
         , DomId ToastOverlayMount
         ]

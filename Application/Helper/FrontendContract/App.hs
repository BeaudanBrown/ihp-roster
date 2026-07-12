{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.App
    ( AppContract
    , App
    , OverlayLane
    , Dialog
    , Picker
    , Toast
    , RosterStaffSortKey
    , Name
    , Role
    , Shifts
    , PageReady
    , LiveFragmentsRefresh
    , InteractionIntent
    , IntentSubmit
    , InteractionSessionStart
    , InteractionSessionEnd
    , InteractionSessionCancelRequest
    , AppContentMount
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

data OverlayLane
data Dialog
data Picker
data Toast

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

data AppContentMount
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
        '[ GlobalSchema (Enum OverlayLane '[Dialog, Picker, Toast])
         , GlobalSchema (Enum RosterStaffSortKey '[Name, Role, Shifts])
         , GlobalSchema (LiteralEnum HtmxActionMethod
            '[ Literal HtmxGet "get"
             , Literal HtmxPost "post"
             , Literal HtmxPut "put"
             , Literal HtmxPatch "patch"
             , Literal HtmxDelete "delete"
             ])
         , GlobalSchema (LiteralEnum HtmxActionSwap
            '[ Literal HtmxInnerHTML "innerHTML"
             , Literal HtmxOuterHTML "outerHTML"
             , Literal HtmxOuterHTMLDashed "outer-html"
             , Literal HtmxBeforeEnd "beforeend"
             , Literal HtmxAfterBegin "afterbegin"
             , Literal HtmxNoneSwap "none"
             ])
         , Event PageReady '[]
         , Event LiveFragmentsRefresh
            '[ Field Scope 'WireSurfaceScope
             , Field ScopeKey 'WireText
             , Field Fragments ('WireList 'WireSurfaceFragmentKey)
             ]
         , Event InteractionIntent '[]
         , Event IntentSubmit '[]
         , Event InteractionSessionStart '[]
         , Event InteractionSessionEnd '[]
         , Event InteractionSessionCancelRequest '[]
         , DomId AppContentMount
         , DomId DialogOverlayMount
         , DomId ToastOverlayMount
         ]

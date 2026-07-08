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
data InteractionIntent
data IntentSubmit
data InteractionSessionStart
data InteractionSessionEnd
data InteractionSessionCancelRequest

data AppContentMount
data DialogOverlayMount
data ToastOverlayMount

type AppContract =
    Global App
        '[ GlobalSchema (Enum OverlayLane '[Dialog, Picker, Toast])
         , GlobalSchema (Enum RosterStaffSortKey '[Name, Role, Shifts])
         , Event PageReady '[]
         , Event LiveFragmentsRefresh '[]
         , Event InteractionIntent '[]
         , Event IntentSubmit '[]
         , Event InteractionSessionStart '[]
         , Event InteractionSessionEnd '[]
         , Event InteractionSessionCancelRequest '[]
         , DomId AppContentMount
         , DomId DialogOverlayMount
         , DomId ToastOverlayMount
         ]

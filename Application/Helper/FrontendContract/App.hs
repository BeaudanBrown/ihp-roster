{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.App
    ( AppContract
    , App
    , OverlayLane
    , Dialog
    , Picker
    , Toast
    , PageReady
    , LiveFragmentsRefresh
    , InteractionIntent
    , IntentSubmit
    , InteractionSessionStart
    , InteractionSessionEnd
    , InteractionSessionCancelRequest
    , DialogOverlayMount
    , ToastOverlayMount
    ) where

import Application.Helper.FrontendContract.DSL

data App

data OverlayLane
data Dialog
data Picker
data Toast

data PageReady
data LiveFragmentsRefresh
data InteractionIntent
data IntentSubmit
data InteractionSessionStart
data InteractionSessionEnd
data InteractionSessionCancelRequest

data DialogOverlayMount
data ToastOverlayMount

type AppContract =
    Global App
        '[ GlobalSchema (Enum OverlayLane '[Dialog, Picker, Toast])
         , Event PageReady '[]
         , Event LiveFragmentsRefresh '[]
         , Event InteractionIntent '[]
         , Event IntentSubmit '[]
         , Event InteractionSessionStart '[]
         , Event InteractionSessionEnd '[]
         , Event InteractionSessionCancelRequest '[]
         , DomId DialogOverlayMount
         , DomId ToastOverlayMount
         ]

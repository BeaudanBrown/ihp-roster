{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Overlay
    ( OverlayContract
    , Overlay
    , DialogSubmitConfig
    , LoadingLabel
    , ToastConfig
    , AutoHideMs
    , DialogOverlayMount
    , ToastOverlayMount
    , DialogMount
    , DialogBackdrop
    , DialogClose
    , DialogSubmit
    , DialogAutoSubmitOnce
    , ToastMount
    , ToastClose
    ) where

import Application.Helper.FrontendContract.DSL

-- | Shared workflow-dialog and toast lane vocabulary. Request actions remain
-- owned by AppShell or a mounted Surface; this contract owns only the generic
-- overlay adapter's browser boundary.
data Overlay

data DialogSubmitConfig
data LoadingLabel

data ToastConfig
data AutoHideMs

data DialogOverlayMount
data ToastOverlayMount

data DialogMount
data DialogBackdrop
data DialogClose
data DialogSubmit
data DialogAutoSubmitOnce
data ToastMount
data ToastClose

type OverlayContract =
    Global Overlay
        '[ BrowserInboundSchema (Record DialogSubmitConfig
            '[ Field LoadingLabel 'WireText
             ])
         , BrowserInboundSchema (Record ToastConfig
            '[ Field AutoHideMs 'WireInt
             ])
         , DomId DialogOverlayMount
         , DomId ToastOverlayMount
         , DomAttr DialogMount
         , DomAttr DialogBackdrop
         , DomAttr DialogClose
         , DomAttr DialogSubmit
         , DomAttr DialogSubmitConfig
         , DomAttr DialogAutoSubmitOnce
         , DomAttr ToastMount
         , DomAttr ToastClose
         , DomAttr ToastConfig
         ]

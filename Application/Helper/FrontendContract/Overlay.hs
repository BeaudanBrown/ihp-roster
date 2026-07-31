{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Overlay
    ( OverlayContract
    , Overlay
    , DialogSubmitConfig
    , LoadingLabel
    , NavigationLoadingConfig
    , LoadingTitle
    , LoadingMessage
    , ToastConfig
    , AutoHideMs
    , DialogOverlayMount
    , ToastOverlayMount
    , DialogMount
    , DialogBackdrop
    , DialogClose
    , DialogDismissed
    , DialogSubmit
    , DialogAutoSubmitOnce
    , DialogBlocking
    , DialogKeyboard
    , DialogFocusRegion
    , NavigationLoading
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

data NavigationLoadingConfig
data LoadingTitle
data LoadingMessage

data ToastConfig
data AutoHideMs

data DialogOverlayMount
data ToastOverlayMount

data DialogMount
data DialogBackdrop
data DialogClose
data DialogDismissed
data DialogSubmit
data DialogAutoSubmitOnce
data DialogBlocking
data DialogKeyboard
data DialogFocusRegion
data NavigationLoading
data ToastMount
data ToastClose

type OverlayContract =
    Global Overlay
        '[ BrowserInboundSchema (Record DialogSubmitConfig
            '[ Field LoadingLabel 'WireText
             ])
         , BrowserInboundSchema (Record NavigationLoadingConfig
            '[ Field LoadingTitle 'WireText
             , Field LoadingMessage 'WireText
             ])
         , BrowserInboundSchema (Record ToastConfig
            '[ Field AutoHideMs 'WireInt
             ])
         , DomId DialogOverlayMount
         , DomId ToastOverlayMount
         , Event DialogDismissed '[]
         , DomAttr DialogMount
         , DomAttr DialogBackdrop
         , DomAttr DialogClose
         , DomAttr DialogSubmit
         , DomAttr DialogSubmitConfig
         , DomAttr DialogAutoSubmitOnce
         , DomAttr DialogBlocking
         , DomAttr DialogKeyboard
         , DomAttr DialogFocusRegion
         , DomAttr NavigationLoading
         , DomAttr NavigationLoadingConfig
         , DomAttr ToastMount
         , DomAttr ToastClose
         , DomAttr ToastConfig
         ]

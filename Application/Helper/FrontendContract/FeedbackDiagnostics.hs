{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.FeedbackDiagnostics
    ( FeedbackDiagnosticsContract
    , FeedbackDiagnostics
    , FeedbackViewportWidthInput
    , FeedbackViewportHeightInput
    , FeedbackDevicePixelRatioInput
    , FeedbackDisplayModeInput
    , FeedbackDisplayMode
    , Browser
    , Standalone
    ) where

import Application.Helper.FrontendContract.DSL

-- Browser-owned measurements are submitted through Haskell-rendered hidden
-- fields. The server still validates every value before persistence.
data FeedbackDiagnostics

data FeedbackViewportWidthInput
data FeedbackViewportHeightInput
data FeedbackDevicePixelRatioInput
data FeedbackDisplayModeInput

data FeedbackDisplayMode
data Browser
data Standalone

type FeedbackDiagnosticsContract =
    Global FeedbackDiagnostics
        '[ BrowserGuardSchema (Enum FeedbackDisplayMode '[Browser, Standalone])
         , DomAttr FeedbackViewportWidthInput
         , DomAttr FeedbackViewportHeightInput
         , DomAttr FeedbackDevicePixelRatioInput
         , DomAttr FeedbackDisplayModeInput
         ]

{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Overlay
    ( OverlayContract
    , Overlay
    , OpenFeedbackDialog
    , SubmitFeedback
    , FeedbackTypeField
    , ContentField
    ) where

import Application.Helper.FrontendContract.App (DialogOverlayMount)
import Application.Helper.FrontendContract.DSL

data Overlay

data OpenFeedbackDialog
data SubmitFeedback
data FeedbackTypeField
data ContentField

type OverlayContract =
    Global Overlay
        '[ OverlayAction OpenFeedbackDialog
            '[]
            '[ OverlayHtmxMethod 'OverlayGet
             , OverlayHtmxTarget DialogOverlayMount
             , OverlayHtmxSwap "innerHTML"
             , OverlayHtmxPushUrl 'OverlayPushUrlFalse
             ]
         , OverlayAction SubmitFeedback
            '[ Field FeedbackTypeField 'WireText
             , Field ContentField 'WireText
             ]
            '[ OverlayHtmxMethod 'OverlayPost
             , OverlayHtmxTarget DialogOverlayMount
             , OverlayHtmxSwap "innerHTML"
             , OverlayHtmxPushUrl 'OverlayPushUrlFalse
             ]
         ]

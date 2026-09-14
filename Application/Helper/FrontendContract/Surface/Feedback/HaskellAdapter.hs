{-# LANGUAGE TypeFamilies #-}
module Application.Helper.FrontendContract.Surface.Feedback.HaskellAdapter where

import Application.Helper.FrontendContract.Surface.HaskellAdapter.Association
import qualified Application.Helper.FrontendContract.Surface.Feedback as Feedback

data FeedbackAdapterFamily
data FeedbackModerationAdapterFamily
instance SurfaceAdapterFamily FeedbackAdapterFamily where
    type AdapterFamilySurface FeedbackAdapterFamily = Feedback.FeedbackSurface
instance SurfaceAdapterFamily FeedbackModerationAdapterFamily where
    type AdapterFamilySurface FeedbackModerationAdapterFamily = Feedback.FeedbackModerationSurface

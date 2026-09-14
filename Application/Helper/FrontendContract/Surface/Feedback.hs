{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
module Application.Helper.FrontendContract.Surface.Feedback where

import Application.Helper.FrontendContract.Surface.DSL
import Generated.Types (FeedbackTypeEnum)

data Feedback
data FeedbackModeration
data FeedbackVenue
data FeedbackPlatform
data VenueId
data FeedbackBoard
data FeedbackCards
data FeedbackReview
data FeedbackDesktopCount
data FeedbackMobileCount
data FeedbackTitle
data FeedbackContent
data FeedbackType
data EditFeedback
data UpdateFeedback
data PublishFeedback
data ArchiveFeedback
data RestoreFeedback
data VoteFeedback
data UnvoteFeedback
data FeedbackVoteControl
data DialogOverlayMount

type FeedbackBoardResource = Resource FeedbackBoard '[]
type FeedbackReviewResource = Resource FeedbackReview '[]
type FeedbackSurface = Surface Feedback
    '[ Scope FeedbackVenue '[Field VenueId 'WireUUID] '[ 'Authorize 'CurrentVenue '[VenueId]]
     , Fragment FeedbackBoard '[] '[ 'MountTarget FeedbackCards '[], 'Eager, 'Live, 'DependsOn FeedbackBoardResource '[]]
     , DomToken FeedbackVoteControl
     , Action VoteFeedback '[] '[ 'HtmxMethod 'HtmxPost, 'HtmxSwap 'HtmxNoSwap, 'HtmxSync ('HtmxSyncOn 'HtmxThis 'HtmxSyncDrop)]
     , Action UnvoteFeedback '[] '[ 'HtmxMethod 'HtmxPost, 'HtmxSwap 'HtmxNoSwap, 'HtmxSync ('HtmxSyncOn 'HtmxThis 'HtmxSyncDrop)]
     ]
type FeedbackModerationSurface = Surface FeedbackModeration
    '[ Scope FeedbackPlatform '[] '[ 'Authorize 'SupportSuperAdmin '[]]
     , Fragment FeedbackDesktopCount '[] '[ 'MountTarget FeedbackDesktopCount '[], 'Eager, 'Live, 'DependsOn FeedbackReviewResource '[]]
     , Fragment FeedbackMobileCount '[] '[ 'MountTarget FeedbackMobileCount '[], 'Eager, 'Live, 'DependsOn FeedbackReviewResource '[]]
     , DomToken DialogOverlayMount
     , Fragment FeedbackReview '[] '[ 'MountTarget FeedbackReview '[], 'Eager, 'Live, 'DependsOn FeedbackReviewResource '[], 'DependsOn FeedbackBoardResource '[]]
     , Action EditFeedback '[] '[ 'HtmxMethod 'HtmxGet, 'HtmxTarget ('HtmxId DialogOverlayMount), 'HtmxSwap 'HtmxInnerHTML]
     , Action UpdateFeedback '[Field FeedbackTitle 'WireText, Field FeedbackContent 'WireText, Field FeedbackType ('WireClosed FeedbackTypeEnum)]
         '[ 'HtmxMethod 'HtmxPost, 'HtmxTarget ('HtmxId DialogOverlayMount), 'HtmxSwap 'HtmxInnerHTML]
     , Action PublishFeedback '[] '[ 'HtmxMethod 'HtmxPost, 'HtmxSwap 'HtmxNoSwap]
     , Action ArchiveFeedback '[] '[ 'HtmxMethod 'HtmxPost, 'HtmxSwap 'HtmxNoSwap]
     , Action RestoreFeedback '[] '[ 'HtmxMethod 'HtmxPost, 'HtmxSwap 'HtmxNoSwap]
     ]

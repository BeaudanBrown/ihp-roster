module Application.Feedback.LiveUpdates where

import qualified Application.Helper.FrontendContract.Surface.Feedback as Surface
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

feedbackSurface :: UUID -> SurfaceImpl Surface.FeedbackSurface
feedbackSurface venueId = mkSurfaceImplFromValues @Surface.FeedbackSurface @Surface.FeedbackVenue
    "primary" (surfaceField @Surface.VenueId venueId &: noSurfaceFields) noSurfaceFields feedbackMountedFragments

feedbackModerationSurface :: SurfaceImpl Surface.FeedbackModerationSurface
feedbackModerationSurface = mkSurfaceImplFromValues @Surface.FeedbackModerationSurface @Surface.FeedbackPlatform
    "primary" noSurfaceFields noSurfaceFields [feedbackReviewMountedFragment]

feedbackMountedFragments :: [FrontendSurfaceMountedFragment]
feedbackMountedFragments = [frontendSurfaceMountedFragmentFor @Surface.FeedbackSurface @Surface.FeedbackBoard
    noSurfaceFields noSurfaceFields "/ShowFeedbackBoard" FrontendSurfaceReplace]

feedbackModerationMountedFragments :: [FrontendSurfaceMountedFragment]
feedbackModerationMountedFragments = [feedbackReviewMountedFragment, feedbackDesktopCountMountedFragment, feedbackMobileCountMountedFragment]

feedbackReviewMountedFragment :: FrontendSurfaceMountedFragment
feedbackReviewMountedFragment = frontendSurfaceMountedFragmentFor @Surface.FeedbackModerationSurface @Surface.FeedbackReview
    noSurfaceFields noSurfaceFields "/ShowFeedbackReview" FrontendSurfaceReplace

feedbackDesktopCountMountedFragment :: FrontendSurfaceMountedFragment
feedbackDesktopCountMountedFragment = frontendSurfaceMountedFragmentFor @Surface.FeedbackModerationSurface @Surface.FeedbackDesktopCount
    noSurfaceFields noSurfaceFields "/ShowFeedbackDesktopCount" FrontendSurfaceReplace

feedbackMobileCountMountedFragment :: FrontendSurfaceMountedFragment
feedbackMobileCountMountedFragment = frontendSurfaceMountedFragmentFor @Surface.FeedbackModerationSurface @Surface.FeedbackMobileCount
    noSurfaceFields noSurfaceFields "/ShowFeedbackMobileCount" FrontendSurfaceReplace

feedbackDesktopCountSurface :: SurfaceImpl Surface.FeedbackModerationSurface
feedbackDesktopCountSurface = mkSurfaceImplFromValues @Surface.FeedbackModerationSurface @Surface.FeedbackPlatform
    "desktop-header" noSurfaceFields noSurfaceFields [feedbackDesktopCountMountedFragment]

feedbackMobileCountSurface :: SurfaceImpl Surface.FeedbackModerationSurface
feedbackMobileCountSurface = mkSurfaceImplFromValues @Surface.FeedbackModerationSurface @Surface.FeedbackPlatform
    "mobile-header" noSurfaceFields noSurfaceFields [feedbackMobileCountMountedFragment]

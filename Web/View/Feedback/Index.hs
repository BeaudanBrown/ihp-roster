module Web.View.Feedback.Index where

import Application.Feedback.LiveUpdates
import Application.Feedback.Management (ManagementFeedbackCard)
import Application.Feedback.ReadModel (PublicFeedbackCard (..))
import Application.Helper.ControllerContext (currentVenueId)
import Application.Helper.FrontendContract.AppShell (OpenFeedbackDialog)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             renderAppShellActionLink)
import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Web.View.Feedback.Card (renderPublicFeedbackCards)
import Web.View.Feedback.Management (renderFeedbackManagement)
import Web.View.Prelude

data IndexView = IndexView { cards :: [PublicFeedbackCard], managementCards :: Maybe [ManagementFeedbackCard] }

instance View IndexView where
    html IndexView { .. } = renderAppPage AppPageConfig
        { appPageTitle = "Feedback"
        , appPageDescription = Nothing
        , appPageActions = renderAddFeedback
        , appPageHelpTopic = Just (PageHelpTopicId "feedback")
        , appPageWidthClass = ""
        , appPageBody = renderAppPanel $ defaultAppPanelConfig [hsx|
            <p>Share your thoughts about what features should be added to Bepis next!</p>
            {feedbackList}
        |]
        }
      where
        feedbackList = case managementCards of
            Just managed -> renderFrontendSurfaceMount feedbackModerationSurface (renderFeedbackManagement managed)
            Nothing -> renderFrontendSurfaceMount (feedbackSurface (unpackId currentVenueId)) (renderPublicFeedbackCards cards)

renderAddFeedback :: Html
renderAddFeedback = renderAppShellActionLink
    (appShellActionByMarker @OpenFeedbackDialog)
    AppShellActionRoute
        { appShellActionRouteUrl = pathTo NewFeedbackAction
        , appShellActionRouteFields = []
        , appShellActionRouteCustomHtmx = []
        , appShellActionRouteStandardUrl = Just (pathTo NewFeedbackAction)
        , appShellActionRouteExtraAttrs = [("class", "btn btn-primary"), ("data-turbolinks", "false")]
        }
    [hsx|Add feedback|]

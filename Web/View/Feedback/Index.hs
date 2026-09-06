module Web.View.Feedback.Index where

import Application.Feedback.ReadModel (PublicFeedbackCard (..))
import Application.Feedback.Management (ManagementFeedbackCard)
import Application.Feedback.LiveUpdates
import Application.Helper.ControllerContext (currentVenueId)
import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Web.View.Feedback.Card (renderPublicFeedbackCards)
import Web.View.Feedback.Management (renderFeedbackManagement)
import Application.Helper.FrontendContract.AppShell (OpenFeedbackDialog)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..), appShellActionByMarker, renderAppShellActionLink)
import Web.View.Prelude

data IndexView = IndexView { cards :: [PublicFeedbackCard], managementCards :: Maybe [ManagementFeedbackCard] }

instance View IndexView where
    html IndexView { .. } = renderAppPage AppPageConfig
        { appPageTitle = "Feedback"
        , appPageDescription = Just "Ideas and improvements shared across Bepis. New feedback is private until reviewed."
        , appPageActions = renderAddFeedback
        , appPageHelpTopic = Nothing
        , appPageWidthClass = ""
        , appPageBody = case managementCards of
            Just managed -> renderFrontendSurfaceMount feedbackModerationSurface (renderFeedbackManagement managed)
            Nothing -> renderFrontendSurfaceMount (feedbackSurface (unpackId currentVenueId)) (renderPublicFeedbackCards cards)
        }

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

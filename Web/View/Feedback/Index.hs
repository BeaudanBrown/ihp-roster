module Web.View.Feedback.Index where

import Application.Feedback.ReadModel (PublicFeedbackCard (..))
import Application.Feedback.Management (ManagementFeedbackCard)
import Application.Feedback.LiveUpdates
import Application.Helper.ControllerContext (currentVenueId)
import qualified Application.Helper.FrontendContract.Surface.Feedback as Surface
import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values (surfaceFragmentTargetId, noSurfaceFields)
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

renderPublicFeedbackCards :: [PublicFeedbackCard] -> Html
renderPublicFeedbackCards cards = [hsx|
    <div id={surfaceFragmentTargetId @Surface.FeedbackSurface @Surface.FeedbackBoard noSurfaceFields} class="d-flex flex-column gap-3">
        {content}
    </div>
|]
  where
    content = case cards of
        [] -> [hsx|<p class="text-muted">No public feedback yet. Add feedback to submit an idea for review.</p>|]
        _ -> forEach cards renderPublicFeedbackCard

renderPublicFeedbackCard :: PublicFeedbackCard -> Html
renderPublicFeedbackCard card = renderAppPanel (defaultAppPanelConfig [hsx|
    <article class="text-break">
        <h2 class="h5">{card.title}</h2>
        <div class="d-flex gap-3 flex-wrap text-muted mb-2">
            <span>{feedbackTypeLabel card.feedbackType}</span>
            <span>Submitted {dateTime card.submittedAt}</span>
            <span>{tshow card.voteCount} votes</span>
        </div>
        <p>{card.description}</p>
    </article>
|])

feedbackTypeLabel :: FeedbackTypeEnum -> Text
feedbackTypeLabel Bug = "Bug"
feedbackTypeLabel Suggestion = "Suggestion"
feedbackTypeLabel Other = "Other"

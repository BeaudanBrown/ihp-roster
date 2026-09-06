module Web.View.Feedback.Management where

import Application.Feedback.Management (ManagementFeedbackCard (..))
import qualified Application.Helper.FrontendContract.Surface.Feedback as Surface
import qualified Application.Helper.FrontendContract.Surface.Feedback.Action as Action
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.FeedbackType (feedbackTypeLabel)
import Web.View.Prelude

feedbackActionRoute :: FeedbackController -> FrontendSurfaceActionRoute
feedbackActionRoute action = FrontendSurfaceActionRoute
    { actionRouteUrl = pathTo action, actionRouteCustomHtmx = []
    , actionRouteStandardUrl = Just (pathTo action), actionRouteExtraAttrs = [] }

renderFeedbackManagement :: [ManagementFeedbackCard] -> Html
renderFeedbackManagement cards = [hsx|
    <div id={surfaceFragmentTargetId @Surface.FeedbackModerationSurface @Surface.FeedbackReview noSurfaceFields} class="app-page-stack">
        {section Private "Private"}
        {section Public "Public"}
        {section Archived "Archived"}
    </div>
|]
  where
    emptySection = [hsx|<p class="text-muted">No feedback in this section.</p>|]
    section :: FeedbackLifecycleEnum -> Text -> Html
    section lifecycle label = [hsx|
        <section class="d-flex flex-column gap-3">
            <h2 class="h4">{label} ({length selected})</h2>
            {if null selected then emptySection else forEach selected renderManagementCard}
        </section>
    |]
      where
        selected = filter (\card -> card.item.lifecycle == lifecycle) cards

renderManagementCard :: ManagementFeedbackCard -> Html
renderManagementCard card = renderAppPanel (defaultAppPanelConfig [hsx|
    <article class="text-break">
        <h3 class="h5">{item.title}</h3>
        <p class="text-muted">{feedbackTypeLabel item.feedbackType} · Submitted {dateTime item.createdAt}</p>
        <p>{item.content}</p>
        <details>
            <summary>Private submission details</summary>
            <dl>
                <dt>Submitter</dt><dd>{card.submitterEmail}</dd>
                <dt>Venue</dt><dd>{card.venueName}</dd>
                <dt>Retained support note</dt><dd>{fromMaybe "None" item.supportNote}</dd>
                <dt>Legacy page</dt><dd>{fromMaybe "Not captured" item.submittedPath}</dd>
                <dt>Legacy role</dt><dd>{fromMaybe "Not captured" item.submittedRole}</dd>
                <dt>Legacy User-Agent</dt><dd>{fromMaybe "Not captured" item.userAgent}</dd>
                <dt>Legacy viewport width / height</dt><dd>{item.viewportWidth} / {item.viewportHeight}</dd>
                <dt>Legacy pixel ratio</dt><dd>{item.devicePixelRatio}</dd>
                <dt>Legacy device / display mode</dt><dd>{item.deviceClass} / {item.displayMode}</dd>
            </dl>
        </details>
        <div class="d-flex gap-2 flex-wrap mt-3">{controls}</div>
    </article>
|])
  where
    item = card.item
    edit = renderFrontendSurfaceActionLink (Action.editFeedbackAction Action.editFeedbackActionFields)
        ((feedbackActionRoute (EditFeedbackAction item.id)) { actionRouteExtraAttrs = [("class", "btn btn-outline-secondary"), ("data-turbolinks", "false")] }) [hsx|Edit|]
    publish = renderFrontendSurfaceActionForm (Action.publishFeedbackAction Action.publishFeedbackActionFields)
        (feedbackActionRoute (PublishFeedbackAction item.id)) [hsx|<button class="btn btn-primary" type="submit">Publish</button>|]
    archive = renderFrontendSurfaceActionForm (Action.archiveFeedbackAction Action.archiveFeedbackActionFields)
        (feedbackActionRoute (ArchiveFeedbackAction item.id)) [hsx|<button class="btn btn-outline-danger" type="submit">Confirm archive</button>|]
    restore = renderFrontendSurfaceActionForm (Action.restoreFeedbackAction Action.restoreFeedbackActionFields)
        (feedbackActionRoute (RestoreFeedbackAction item.id)) [hsx|<button class="btn btn-outline-secondary" type="submit">Restore</button>|]
    controls = case item.lifecycle of
        Private -> [hsx|{edit}{publish}{archive}|]
        Public -> [hsx|{edit}<details><summary class="btn btn-outline-danger">Archive</summary><p>Archive this public feedback? All votes will be removed.</p>{archive}</details>|]
        Archived -> restore

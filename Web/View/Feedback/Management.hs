module Web.View.Feedback.Management where

import Application.Feedback.Management (ManagementFeedbackCard (..))
import qualified Application.Helper.FrontendContract.Surface.Feedback as Surface
import qualified Application.Helper.FrontendContract.Surface.Feedback.Action as Action
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.FeedbackType (feedbackTypeLabel)
import Web.View.Feedback.Card (renderFeedbackVote)
import Web.View.Prelude

feedbackActionRoute :: FeedbackController -> FrontendSurfaceActionRoute
feedbackActionRoute action = FrontendSurfaceActionRoute
    { actionRouteUrl = pathTo action, actionRouteCustomHtmx = []
    , actionRouteStandardUrl = Just (pathTo action), actionRouteExtraAttrs = [] }

renderFeedbackManagement :: [ManagementFeedbackCard] -> Html
renderFeedbackManagement cards = [hsx|
    <div id={surfaceFragmentTargetId @Surface.FeedbackModerationSurface @Surface.FeedbackReview noSurfaceFields} class="app-page-stack">
        {section Public "Public"}
        {section Private "Private"}
        {section Archived "Archived"}
    </div>
|]
  where
    emptySection = [hsx|<p class="text-muted">No feedback in this section.</p>|]
    section :: FeedbackLifecycleEnum -> Text -> Html
    section lifecycle label = [hsx|
        <section class="d-flex flex-column gap-3">
            <h2 class="h4">{label} ({length selected})</h2>
            {if null selected then emptySection else renderManagementTable label selected}
        </section>
    |]
      where
        selected = filter (\card -> card.item.lifecycle == lifecycle) cards

renderManagementTable :: Text -> [ManagementFeedbackCard] -> Html
renderManagementTable label cards = [hsx|
    <div class="table-responsive" role="region" aria-label={label <> " feedback"} tabindex="0">
        <table class="table align-middle mb-0" aria-label={label <> " feedback"}>
            <thead>
                <tr>
                    <th scope="col">Title</th>
                    <th scope="col">Content</th>
                    <th scope="col">Type</th>
                    <th scope="col">Submitted</th>
                    <th scope="col">Submitter</th>
                    <th scope="col">Venue</th>
                    <th scope="col">Votes</th>
                    <th scope="col">Actions</th>
                </tr>
            </thead>
            <tbody>{forEach cards renderManagementRow}</tbody>
        </table>
    </div>
|]

renderManagementRow :: ManagementFeedbackCard -> Html
renderManagementRow card = [hsx|
    <tr>
        <th scope="row" class="text-break">{item.title}</th>
        <td class="text-break">{item.content}</td>
        <td>{feedbackTypeLabel item.feedbackType}</td>
        <td class="text-nowrap">{dateTime item.createdAt}</td>
        <td>{card.submitterEmail}</td>
        <td>{card.venueName}</td>
        <td>{votes}</td>
        <td><div class="d-flex gap-2 flex-wrap">{controls}</div></td>
    </tr>
|]
  where
    item = card.item
    votes = maybe [hsx|<span class="text-muted">Not available</span>|] renderFeedbackVote card.publicCard
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

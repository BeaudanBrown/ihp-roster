module Web.View.Feedback.Card (renderPublicFeedbackCards, renderFeedbackVote) where

import Application.Feedback.ReadModel (PublicFeedbackCard (..))
import Application.Helper.FeedbackType (feedbackTypeLabel)
import qualified Application.Helper.FrontendContract.Surface.Feedback as Surface
import qualified Application.Helper.FrontendContract.Surface.Feedback.Action as Action
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.Text as Text
import Web.View.Prelude

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
            <span>{Text.toTitle (feedbackTypeLabel card.feedbackType)}</span>
            <span>Submitted {dateTime card.submittedAt}</span>
        </div>
        <p>{card.description}</p>
        {renderFeedbackVote card}
    </article>
|])

-- Native stable identity lets the generic live-fragment focus owner preserve
-- this control as server ordering changes. Only the viewer's own state crosses
-- the public projection; no vote-user ids or provenance are rendered.
renderFeedbackVote :: PublicFeedbackCard -> Html
renderFeedbackVote card = renderFrontendSurfaceActionForm action route [hsx|
    <div class="d-flex gap-2 align-items-center flex-wrap">
        <button id={controlId} class="btn btn-outline-primary" type="submit"
                aria-label={"Vote for " <> card.title} aria-pressed={if card.viewerHasVoted then "true" else "false" :: Text}
                aria-describedby={countId}>
            {if card.viewerHasVoted then "Voted — undo" else "Vote" :: Text}
        </button>
        <span id={countId}>{tshow card.voteCount} votes</span>
        <span class="htmx-indicator text-muted" role="status">Saving vote…</span>
    </div>
|]
  where
    controlId = surfaceDomTokenValue @Surface.FeedbackSurface @Surface.FeedbackVoteControl <> "-" <> tshow (unpackId card.feedbackId)
    countId = controlId <> "-count"
    action = if card.viewerHasVoted then Action.unvoteFeedbackAction Action.unvoteFeedbackActionFields else Action.voteFeedbackAction Action.voteFeedbackActionFields
    url = pathTo (if card.viewerHasVoted then UnvoteFeedbackAction card.feedbackId else VoteFeedbackAction card.feedbackId)
    route = FrontendSurfaceActionRoute
        { actionRouteUrl = url, actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Just url, actionRouteExtraAttrs = [] }

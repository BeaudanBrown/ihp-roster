module Web.View.Feedback.Edit where

import qualified Application.Helper.FrontendContract.Surface.Feedback as Surface
import qualified Application.Helper.FrontendContract.Surface.Feedback.Action as Action
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Web.View.Feedback.Management (feedbackActionRoute)
import Web.View.Feedback.New (renderFeedbackFieldError, renderFeedbackTypeOption)
import Web.View.Prelude

newtype EditView = EditView { feedbackItem :: UserFeedbackItem }
instance View EditView where
    html EditView { .. } = renderPageDialogModal (pathTo FeedbackAction) (editDialog PageOverlayForm feedbackItem)

renderEditFeedbackDialog :: UserFeedbackItem -> Html
renderEditFeedbackDialog = renderDialogOverlay . editDialog HtmxOverlayForm

editDialog :: OverlayFormMode -> UserFeedbackItem -> DialogOverlayConfig
editDialog mode item = DialogOverlayConfig
    { dialogOverlayTitle = "Edit feedback"
    , dialogOverlayBody = editForm mode item
    , dialogOverlayStartButtons = []
    , dialogOverlayButtons = defaultOverlayButtons "feedback-edit-form"
    , dialogOverlayDialogClass = "" }

editForm :: OverlayFormMode -> UserFeedbackItem -> Html
editForm mode item = case mode of
    HtmxOverlayForm -> renderFrontendSurfaceActionForm (Action.updateFeedbackAction fields)
        ((feedbackActionRoute (UpdateFeedbackAction item.id)) { actionRouteExtraAttrs = [("id", "feedback-edit-form")] }) controls
    PageOverlayForm -> [hsx|<form id="feedback-edit-form" method="POST" action={UpdateFeedbackAction item.id}>{controls}</form>|]
  where
    fields = Action.updateFeedbackActionFields item.title item.content item.feedbackType
    controls = [hsx|
        {renderFeedbackFieldError item "editorial"}
        <div class="mb-3">
            <label for="feedback-edit-title" class="form-label">Title</label>
            <input id="feedback-edit-title" class="form-control" type="text" name={surfaceFieldNameFrom @Surface.FeedbackTitle fields} value={item.title} maxlength="120" required="required" />
        </div>
        <div class="mb-3">
            <label for="feedback-edit-type" class="form-label">Type</label>
            <select id="feedback-edit-type" class="form-select" name={surfaceFieldNameFrom @Surface.FeedbackType fields}>
                {renderFeedbackTypeOption item Bug "Bug"}
                {renderFeedbackTypeOption item Suggestion "Suggestion"}
                {renderFeedbackTypeOption item Other "Other"}
            </select>
        </div>
        <div class="mb-3">
            <label for="feedback-edit-content" class="form-label">Description</label>
            <textarea id="feedback-edit-content" class="form-control" rows="6" name={surfaceFieldNameFrom @Surface.FeedbackContent fields} minlength="3" maxlength="3000" required="required">{item.content}</textarea>
        </div>
    |]

{-# LANGUAGE TypeApplications #-}

module Web.View.Feedback.New where

import Application.Helper.FrontendContract.AppShell (SubmitFeedback)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             renderAppShellActionForm)
import qualified Data.Text as Text
import Web.View.Prelude

newtype NewView = NewView
    { feedbackItem :: UserFeedbackItem
    }

instance View NewView where
    html NewView { .. } =
        renderPageDialogModal
            (pathTo RosterWeeksAction)
            (feedbackDialogConfig PageOverlayForm feedbackItem)

feedbackFormId :: Text
feedbackFormId = "feedback-form"

renderNewFeedbackDialog :: UserFeedbackItem -> Html
renderNewFeedbackDialog feedbackItem =
    renderDialogOverlay (feedbackDialogConfig HtmxOverlayForm feedbackItem)

feedbackDialogConfig :: OverlayFormMode -> UserFeedbackItem -> DialogOverlayConfig
feedbackDialogConfig formMode feedbackItem =
    DialogOverlayConfig
        { dialogOverlayTitle = "Send Feedback"
        , dialogOverlayBody = renderFeedbackForm formMode feedbackItem
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = defaultOverlayButtons feedbackFormId
        , dialogOverlayDialogClass = ""
        }

renderFeedbackForm :: OverlayFormMode -> UserFeedbackItem -> Html
renderFeedbackForm formMode feedbackItem =
    case formMode of
        HtmxOverlayForm ->
            renderAppShellActionForm
                (appShellActionByMarker @SubmitFeedback)
                AppShellActionRoute
                    { appShellActionRouteUrl = pathTo CreateFeedbackAction
                    , appShellActionRouteFields = []
                    , appShellActionRouteCustomHtmx = []
                    , appShellActionRouteStandardUrl = Nothing
                    , appShellActionRouteExtraAttrs =
                        [ ("id", feedbackFormId)
                        , ("data-disable-javascript-submission", "true")
                        ]
                    }
                (renderFeedbackFormFields feedbackItem)
        PageOverlayForm -> [hsx|
            <form id={feedbackFormId}
                  method="POST"
                  action={CreateFeedbackAction}>
                {renderFeedbackFormFields feedbackItem}
            </form>
        |]

renderFeedbackFormFields :: UserFeedbackItem -> Html
renderFeedbackFormFields feedbackItem = [hsx|
    <div class="app-form-width">
        <div class="mb-3">
            <label class="form-label" for="feedback-type">Type</label>
            <select id="feedback-type" name="feedbackType" class={classes [("form-select", True), ("is-invalid", feedbackHasErrorFor feedbackItem "feedbackType")]}>
                {renderFeedbackTypeOption feedbackItem "bug" "Bug"}
                {renderFeedbackTypeOption feedbackItem "suggestion" "Suggestion"}
                {renderFeedbackTypeOption feedbackItem "other" "Other"}
            </select>
            {renderFeedbackFieldError feedbackItem "feedbackType"}
        </div>

        <div class="mb-3">
            <label class="form-label" for="feedback-content">Feedback</label>
            <textarea
                id="feedback-content"
                name="content"
                rows="6"
                class={classes [("form-control", True), ("is-invalid", feedbackHasErrorFor feedbackItem "content")]}
                required="required"
            >{feedbackItem.content}</textarea>
            <div class="form-text">A short note is fine. Maximum 3000 characters.</div>
            {renderFeedbackFieldError feedbackItem "content"}
        </div>
    </div>
|]

renderFeedbackTypeOption :: UserFeedbackItem -> Text -> Text -> Html
renderFeedbackTypeOption feedbackItem value label = [hsx|
    <option value={value} selected={feedbackItem.feedbackType == value}>{label}</option>
|]

renderFeedbackFieldError :: UserFeedbackItem -> Text -> Html
renderFeedbackFieldError feedbackItem fieldName =
    case lookup fieldName feedbackItem.meta.annotations of
        Just (TextViolation msg) -> [hsx|<div class="invalid-feedback d-block">{msg}</div>|]
        Just (HtmlViolation msg) -> [hsx|<div class="invalid-feedback d-block">{msg}</div>|]
        Nothing -> mempty

feedbackHasErrorFor :: UserFeedbackItem -> Text -> Bool
feedbackHasErrorFor feedbackItem fieldName = isJust (lookup fieldName feedbackItem.meta.annotations)

feedbackContentPreview :: Text -> Text
feedbackContentPreview content =
    let stripped = Text.strip content
     in if Text.length stripped > 160
            then Text.take 157 stripped <> "..."
            else stripped

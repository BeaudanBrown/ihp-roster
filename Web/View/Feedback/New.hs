{-# LANGUAGE TypeApplications #-}

module Web.View.Feedback.New where

import Application.Helper.FrontendContract.AppShell (ContentField, FeedbackTitleField,
                                                     FeedbackTypeField, SubmitFeedback)
import Application.Helper.FrontendContract.AppShell.Request (AppShellActionFields,
                                                             appShellActionFields,
                                                             appShellActionFor)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             defaultAppShellActionRoute,
                                                             renderAppShellActionForm)
import Application.Helper.FrontendContract.Surface.Values
import Web.View.Prelude

newtype NewView = NewView
    { feedbackItem :: UserFeedbackItem
    }

instance View NewView where
    html NewView { .. } =
        renderPageDialogModal
            (pathTo FeedbackAction)
            (feedbackDialogConfig PageOverlayForm feedbackItem)

feedbackFormId :: Text
feedbackFormId = "feedback-form"

renderNewFeedbackDialog :: UserFeedbackItem -> Html
renderNewFeedbackDialog feedbackItem =
    renderDialogOverlay (feedbackDialogConfig HtmxOverlayForm feedbackItem)

feedbackDialogConfig :: OverlayFormMode -> UserFeedbackItem -> DialogOverlayConfig
feedbackDialogConfig formMode feedbackItem =
    defaultDialogOverlayConfig
            "Add feedback"
            (renderFeedbackForm formMode feedbackItem)
            (defaultOverlayButtons feedbackFormId)

renderFeedbackForm :: OverlayFormMode -> UserFeedbackItem -> Html
renderFeedbackForm formMode feedbackItem =
    case formMode of
        HtmxOverlayForm ->
            renderAppShellActionForm
                (appShellActionFor fields)
                ((defaultAppShellActionRoute (pathTo CreateFeedbackAction))
                    { appShellActionRouteExtraAttrs = [ ("id", feedbackFormId)

                        ]
                    })
                (renderFeedbackFormFields fields feedbackItem)
        PageOverlayForm -> [hsx|
            <form id={feedbackFormId}
                  method="POST"
                  action={CreateFeedbackAction}>
                {renderFeedbackFormFields fields feedbackItem}
            </form>
        |]
  where
    fields =
        appShellActionFields @SubmitFeedback
            (surfaceField @FeedbackTypeField feedbackItem.feedbackType)
            ( surfaceField @ContentField feedbackItem.content
                &: surfaceField @FeedbackTitleField feedbackItem.title
                &: noSurfaceFields
            )

renderFeedbackFormFields :: AppShellActionFields SubmitFeedback -> UserFeedbackItem -> Html
renderFeedbackFormFields fields feedbackItem = [hsx|
    <div class="app-form-width">
        <div class="mb-3">
            <label class="form-label" for="feedback-title">Title</label>
            <input id="feedback-title" name={surfaceFieldNameFrom @FeedbackTitleField fields}
                value={feedbackItem.title} type="text" maxlength="120" required="required"
                class={classes [("form-control", True), ("is-invalid", feedbackHasErrorFor feedbackItem "title")]} />
            {renderFeedbackFieldError feedbackItem "title"}
        </div>
        <div class="mb-3">
            <label class="form-label" for="feedback-type">Type</label>
            <select id="feedback-type" name={surfaceFieldNameFrom @FeedbackTypeField fields} class={classes [("form-select", True), ("is-invalid", feedbackHasErrorFor feedbackItem "feedbackType")]}>
                {renderFeedbackTypeOption feedbackItem Bug "Bug"}
                {renderFeedbackTypeOption feedbackItem Suggestion "Suggestion"}
                {renderFeedbackTypeOption feedbackItem Other "Other"}
            </select>
            {renderFeedbackFieldError feedbackItem "feedbackType"}
        </div>

        <div class="mb-3">
            <label class="form-label" for="feedback-content">Description</label>
            <textarea
                id="feedback-content"
                name={surfaceFieldNameFrom @ContentField fields}
                rows="6"
                minlength="3"
                maxlength="3000"
                class={classes [("form-control", True), ("is-invalid", feedbackHasErrorFor feedbackItem "content")]}
                required="required"
            >{feedbackItem.content}</textarea>
            <div class="form-text">A short note is fine. Maximum 3000 characters.</div>
            {renderFeedbackFieldError feedbackItem "content"}
        </div>
    </div>
|]

renderFeedbackTypeOption :: UserFeedbackItem -> FeedbackTypeEnum -> Text -> Html
renderFeedbackTypeOption feedbackItem value label = [hsx|
    <option value={wireValue} selected={feedbackItem.feedbackType == value}>{label}</option>
|]
  where
    wireValue = inputValue value

renderFeedbackFieldError :: UserFeedbackItem -> Text -> Html
renderFeedbackFieldError feedbackItem fieldName =
    case lookup fieldName feedbackItem.meta.annotations of
        Just (TextViolation msg) -> [hsx|<div class="invalid-feedback d-block">{msg}</div>|]
        Just (HtmlViolation msg) -> [hsx|<div class="invalid-feedback d-block">{msg}</div>|]
        Nothing -> mempty

feedbackHasErrorFor :: UserFeedbackItem -> Text -> Bool
feedbackHasErrorFor feedbackItem fieldName = isJust (lookup fieldName feedbackItem.meta.annotations)

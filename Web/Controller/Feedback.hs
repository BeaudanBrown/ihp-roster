module Web.Controller.Feedback where

import Application.Feedback.ReadModel (fetchPublicFeedbackCards)
import Application.Feedback.Notification (enqueueFeedbackNotificationJobs,
                                          feedbackSubmittedMailKind)
import Application.Helper.Controller (boundedText, normalizeTextField)
import Application.Helper.FrontendContract.AppShell (ContentField, FeedbackTitleField,
                                                     FeedbackTypeField, SubmitFeedback)
import Application.Helper.FrontendContract.AppShell.Request (AppShellActionFields,
                                                             parseAppShellActionParams)
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.Telemetry (addTelemetryEvent)
import Application.Helper.View (ToastOverlayPosition (..),
                                renderDialogOverlayClearOob, renderToastOob,
                                successToast)
import Data.Coerce (coerce)
import qualified Data.Text as Text
import OpenTelemetry.Attributes (toAttribute)
import Web.Controller.Prelude
import Web.View.Feedback.Index
import Web.View.Feedback.New

instance Controller FeedbackController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect

    action currentAction@FeedbackAction = runBepis currentAction BepisPageAction do
        cards <- fetchPublicFeedbackCards
        render IndexView { .. }

    action currentAction@NewFeedbackAction = runBepis currentAction BepisFormAction do
        let feedbackItem = buildNewFeedbackItem
        if isHtmxRequest
            then respondHtml (renderNewFeedbackDialog feedbackItem)
            else render NewView { .. }

    action currentAction@CreateFeedbackAction = runBepis currentAction BepisMutationAction do
        case parseAppShellActionParams @SubmitFeedback of
            Left errors -> do
                let errorSummary = surfaceRequestFieldErrorsMessage errors
                let feedbackItem =
                        if "feedbackType" `Text.isInfixOf` errorSummary
                            then buildNewFeedbackItem |> attachFailure #feedbackType "Choose a feedback type"
                            else if "feedbackTitle" `Text.isInfixOf` errorSummary
                                then buildNewFeedbackItem |> attachFailure #title "Please enter a title"
                                else buildNewFeedbackItem |> attachFailure #content "Please enter at least 3 characters"
                renderInvalidFeedback feedbackItem
            Right fields -> do
                let feedbackItem = buildSubmittedFeedbackItem fields
                feedbackItem
                    |> ifValid \case
                        Left invalidFeedbackItem -> renderInvalidFeedback invalidFeedbackItem
                        Right validFeedbackItem -> do
                            notificationJobs <- withTransaction do
                                persistedFeedbackItem <- validFeedbackItem |> createRecord
                                enqueueFeedbackNotificationJobs persistedFeedbackItem
                            addTelemetryEvent
                                "bepis.email.enqueue"
                                [ ("mail.kind", toAttribute feedbackSubmittedMailKind)
                                , ("recipient.count", toAttribute (length notificationJobs))
                                ]
                            if isHtmxRequest
                                then respondHtml [hsx|
                                    {renderDialogOverlayClearOob}
                                    {renderToastOob ToastBottomCenter (successToast "Thanks — your feedback was submitted for review.")}
                                |]
                                else do
                                    setSuccessMessage "Thanks — your feedback was submitted for review."
                                    redirectTo FeedbackAction
      where
        renderInvalidFeedback feedbackItem =
            if isHtmxRequest
                then respondHtml (renderNewFeedbackDialog feedbackItem)
                else render NewView { .. }

buildNewFeedbackItem :: (?context :: ControllerContext, ?request :: Request) => UserFeedbackItem
buildNewFeedbackItem =
    newRecord @UserFeedbackItem
        |> set #venueId (coerce currentVenueId)
        |> set #submittedByUserId (coerce effectiveCurrentUser.id)
        |> set #title ""
        |> set #feedbackType Bug
        |> set #lifecycle Private
        |> set #content ""

buildSubmittedFeedbackItem :: (?context :: ControllerContext, ?request :: Request) => AppShellActionFields SubmitFeedback -> UserFeedbackItem
buildSubmittedFeedbackItem fields =
    buildNewFeedbackItem
        |> set #feedbackType (surfaceFieldValue @FeedbackTypeField fields)
        |> set #title (surfaceFieldValue @FeedbackTitleField fields)
        |> normalizeTextField #title
        |> validateField #title nonEmpty
        |> validateField #title (boundedText 120)
        |> set #content (surfaceFieldValue @ContentField fields)
        |> normalizeTextField #content
        |> validateField #content nonEmpty
        |> validateField #content feedbackContentMinLength
        |> validateField #content (boundedText 3000)

feedbackContentMinLength :: Text -> ValidatorResult
feedbackContentMinLength content
    | Text.length content >= 3 = Success
    | otherwise = Failure "Please enter at least 3 characters"

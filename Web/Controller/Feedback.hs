module Web.Controller.Feedback where

import Application.Feedback.ReadModel (fetchPublicFeedbackCards)
import Application.Feedback.Notification (feedbackSubmittedMailKind)
import Application.Feedback.Management
import Application.Helper.Feedback (PrivateFeedbackCount (..), fetchPrivateFeedbackCount)
import Web.View.Layout (renderFeedbackDesktopCount, renderFeedbackMobileCount)
import Application.Feedback.LiveUpdates
import qualified Application.Feedback.Mutations as Mutations
import Application.Feedback.Domain (FeedbackMutationError (..))
import qualified Application.Helper.FrontendContract.Surface.Feedback as Surface
import qualified Application.Helper.FrontendContract.Surface.Feedback.Action as Action
import Application.Helper.FrontendContract.Surface.Feedback.Live
import Application.Helper.SurfaceResource
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh)
import Application.Helper.Controller (boundedText, normalizeTextField)
import Application.Helper.FrontendContract.AppShell (ContentField, FeedbackTitleField,
                                                     FeedbackTypeField, SubmitFeedback)
import Application.Helper.FrontendContract.AppShell.Request (AppShellActionFields,
                                                             parseAppShellActionParams)
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue, surfaceFieldNameFrom)
import Application.Helper.Telemetry (addTelemetryEvent)
import Application.Helper.View (ToastOverlayPosition (..),
                                renderDialogOverlayClearOob, renderToastOob,
                                successToast, errorToast)
import Data.Coerce (coerce)
import qualified Data.Text as Text
import OpenTelemetry.Attributes (toAttribute)
import Web.Controller.Prelude
import Web.View.Feedback.Index
import Web.View.Feedback.New
import Web.View.Feedback.Edit
import Web.View.Feedback.Management (renderFeedbackManagement)

instance Controller FeedbackController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect

    action currentAction@FeedbackAction = runBepis currentAction BepisPageAction do
        cards <- fetchPublicFeedbackCards
        managementCards <- if currentUserIsUnimpersonatedSuperAdmin then Just <$> fetchManagementFeedbackCards else pure Nothing
        render IndexView { .. }

    action currentAction@ShowFeedbackBoardAction = runBepis currentAction BepisPageAction do
        fetchPublicFeedbackCards >>= respondHtml . renderPublicFeedbackCards

    action currentAction@ShowFeedbackReviewAction = runBepis currentAction BepisPageAction do
        fetchManagementFeedbackCards >>= respondHtml . renderFeedbackManagement

    action currentAction@ShowFeedbackDesktopCountAction = runBepis currentAction BepisPageAction do
        ensureFeedbackModeration
        PrivateFeedbackCount count <- fetchPrivateFeedbackCount
        respondHtml (renderFeedbackDesktopCount count)

    action currentAction@ShowFeedbackMobileCountAction = runBepis currentAction BepisPageAction do
        ensureFeedbackModeration
        PrivateFeedbackCount count <- fetchPrivateFeedbackCount
        respondHtml (renderFeedbackMobileCount count)

    action currentAction@EditFeedbackAction { feedbackItemId } = runBepis currentAction BepisFormAction do
        ensureFeedbackModeration
        withEditableFeedback feedbackItemId respondEditFeedback

    action currentAction@UpdateFeedbackAction { feedbackItemId } = runBepis currentAction BepisMutationAction do
        ensureFeedbackModeration
        withEditableFeedback feedbackItemId \original -> case Action.parseUpdateFeedbackActionParams of
            Left errors -> do
                let names = Action.updateFeedbackActionFields original.title original.content original.feedbackType
                let submitted = original
                        |> set #title (fromMaybe "" (paramOrNothing @Text (cs (surfaceFieldNameFrom @Surface.FeedbackTitle names))))
                        |> set #content (fromMaybe "" (paramOrNothing @Text (cs (surfaceFieldNameFrom @Surface.FeedbackContent names))))
                        |> attachFailure #editorial (surfaceRequestFieldErrorsMessage errors)
                respondEditFeedback submitted
            Right fields -> do
                let title = surfaceFieldValue @Surface.FeedbackTitle fields
                let content = surfaceFieldValue @Surface.FeedbackContent fields
                let feedbackType = surfaceFieldValue @Surface.FeedbackType fields
                result <- Mutations.editFeedback feedbackItemId title content feedbackType
                case result.liveMutationValue of
                    Left failure -> respondEditFeedback (original |> set #title title |> set #content content |> set #feedbackType feedbackType |> attachFailure #editorial (feedbackMutationErrorMessage failure))
                    Right _ -> respondModerationSuccess result

    action currentAction@PublishFeedbackAction { feedbackItemId } = runBepis currentAction BepisMutationAction do
        ensureFeedbackModeration
        Mutations.publishFeedback feedbackItemId >>= respondModerationResult

    action currentAction@ArchiveFeedbackAction { feedbackItemId } = runBepis currentAction BepisMutationAction do
        ensureFeedbackModeration
        Mutations.archiveFeedback feedbackItemId >>= respondModerationResult

    action currentAction@RestoreFeedbackAction { feedbackItemId } = runBepis currentAction BepisMutationAction do
        ensureFeedbackModeration
        Mutations.restoreFeedback feedbackItemId >>= respondModerationResult

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
                            submission <- Mutations.submitFeedback validFeedbackItem
                            let notificationJobs = submission.liveMutationValue
                            addTelemetryEvent
                                "bepis.email.enqueue"
                                [ ("mail.kind", toAttribute feedbackSubmittedMailKind)
                                , ("recipient.count", toAttribute (length notificationJobs))
                                ]
                            if isHtmxRequest
                                then do
                                    setFeedbackActorRefresh submission
                                    respondHtml [hsx|
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

withEditableFeedback :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id UserFeedbackItem -> (UserFeedbackItem -> IO ()) -> IO ()
withEditableFeedback itemId useFeedback = do
    item <- query @UserFeedbackItem |> filterWhere (#id, itemId) |> fetchOneOrNothing
    case item of
        Just feedback | feedback.lifecycle /= Archived -> useFeedback feedback
        _ -> renderNotFound

respondEditFeedback :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => UserFeedbackItem -> IO ()
respondEditFeedback feedbackItem = if isHtmxRequest
    then respondHtml (renderEditFeedbackDialog feedbackItem)
    else render EditView { .. }

respondModerationResult :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LiveMutationResult (Either FeedbackMutationError UserFeedbackItem) -> IO ()
respondModerationResult result = case result.liveMutationValue of
    Left FeedbackNotFound -> renderNotFound
    Left failure -> if isHtmxRequest
        then respondHtml (renderToastOob ToastBottomCenter (errorToast (feedbackMutationErrorMessage failure)))
        else setErrorMessage (feedbackMutationErrorMessage failure) >> redirectTo FeedbackAction
    Right _ -> respondModerationSuccess result

respondModerationSuccess :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LiveMutationResult a -> IO ()
respondModerationSuccess result = if isHtmxRequest
    then do
        setFeedbackActorRefresh result
        respondHtml [hsx|
            {renderDialogOverlayClearOob}
            {renderToastOob ToastBottomCenter (successToast "Feedback updated.")}
        |]
    else setSuccessMessage "Feedback updated." >> redirectTo FeedbackAction

setFeedbackActorRefresh :: (?context :: ControllerContext, ?request :: Request) => LiveMutationResult a -> IO ()
setFeedbackActorRefresh result = do
    setHeader ("HX-Reswap", "none")
    if currentUserIsUnimpersonatedSuperAdmin
        then setActorLiveResourcesRefresh feedbackPlatformLiveScope result.liveMutationTouchedResources feedbackModerationMountedFragments
        else setActorLiveResourcesRefresh (feedbackVenueLiveScope (unpackId currentVenueId)) result.liveMutationTouchedResources feedbackMountedFragments

feedbackMutationErrorMessage :: FeedbackMutationError -> Text
feedbackMutationErrorMessage = \case
    FeedbackNotFound -> "Feedback not found."
    FeedbackInvalidTransition -> "This feedback changed. Refresh and try again."
    FeedbackInvalidTitle -> "Enter a title between 1 and 120 characters."
    FeedbackInvalidContent -> "Enter a description between 3 and 3000 characters."
    FeedbackAlreadyVoted -> "Already voted."
    FeedbackVoteNotFound -> "Vote not found."

feedbackContentMinLength :: Text -> ValidatorResult
feedbackContentMinLength content
    | Text.length content >= 3 = Success
    | otherwise = Failure "Please enter at least 3 characters"

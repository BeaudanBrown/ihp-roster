module Web.Controller.Feedback where

import Application.Helper.Controller (boundedText, normalizeTextField,
                                      requireParam)
import Application.Helper.View (ToastOverlayPosition (..), dialogOverlayMountId,
                                renderToastOob, successToast)
import Data.Coerce (coerce)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Text.Encoding.Error as TextEncodingError
import IHP.ControllerSupport (getRequestPathAndQuery)
import qualified Network.Wai as Wai
import Web.Controller.Prelude
import Web.View.Feedback.New

feedbackMutationSpec :: BepisMutationSpec
feedbackMutationSpec = BepisMutationSpec
    { auditPolicy = BepisAuditNotRequired
    , realtimePolicy = BepisNoRealtimeInvalidation
    , scopePolicy = BepisCurrentVenueScope
    }

instance Controller FeedbackController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect

    action currentAction@NewFeedbackAction = bepisFormAction currentAction do
        let feedbackItem = buildNewFeedbackItem
        if isHtmxRequest
            then respondHtml (renderNewFeedbackDialog feedbackItem)
            else render NewView { .. }

    action currentAction@CreateFeedbackAction = bepisMutationAction currentAction feedbackMutationSpec do
        let feedbackItem = buildSubmittedFeedbackItem
        feedbackItem
            |> ifValid \case
                Left feedbackItem ->
                    if isHtmxRequest
                        then respondHtml (renderNewFeedbackDialog feedbackItem)
                        else render NewView { .. }
                Right feedbackItem -> do
                    _ <- feedbackItem |> createRecord
                    if isHtmxRequest
                        then respondHtml [hsx|
                            <div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>
                            {renderToastOob ToastBottomCenter (successToast "Thanks — your feedback was sent.")}
                        |]
                        else do
                            setSuccessMessage "Thanks — your feedback was sent."
                            redirectTo RosterWeeksAction

buildNewFeedbackItem :: (?context :: ControllerContext, ?request :: Request) => UserFeedbackItem
buildNewFeedbackItem =
    newRecord @UserFeedbackItem
        |> set #venueId (coerce currentVenueId)
        |> set #submittedByUserId (coerce currentUser.id)
        |> set #feedbackType "bug"
        |> set #status "new"
        |> set #priority "normal"
        |> set #content ""

buildSubmittedFeedbackItem :: (?context :: ControllerContext, ?request :: Request) => UserFeedbackItem
buildSubmittedFeedbackItem =
    buildNewFeedbackItem
        |> requireParam #content "content" "Please enter your feedback"
        |> fill @'["feedbackType", "content"]
        |> normalizeTextField #content
        |> validateField #feedbackType validateFeedbackType
        |> validateField #content nonEmpty
        |> validateField #content feedbackContentMinLength
        |> validateField #content (boundedText 3000)
        |> set #submittedPath (Just currentRequestPathOnly)
        |> set #userAgent currentUserAgent

feedbackContentMinLength :: Text -> ValidatorResult
feedbackContentMinLength content
    | Text.length content >= 3 = Success
    | otherwise = Failure "Please enter at least 3 characters"

validateFeedbackType :: Text -> ValidatorResult
validateFeedbackType feedbackType
    | feedbackType `elem` allowedFeedbackTypes = Success
    | otherwise = Failure "Choose a feedback type"

allowedFeedbackTypes :: [Text]
allowedFeedbackTypes = ["bug", "suggestion", "other"]

currentRequestPathOnly :: (?request :: Request) => Text
currentRequestPathOnly =
    Text.takeWhile (/= '?') (TextEncoding.decodeUtf8 getRequestPathAndQuery)

currentUserAgent :: (?request :: Request) => Maybe Text
currentUserAgent = do
    rawUserAgent <- lookup "User-Agent" (Wai.requestHeaders ?request)
    pure (Text.take 500 (TextEncoding.decodeUtf8With TextEncodingError.lenientDecode rawUserAgent))
